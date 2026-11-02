package duoworkflow

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"time"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/api"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/helper/fail"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/log"
)

// defaultDetachedAcceptTimeout is how long the handler waits, once the start
// request is sent, for Duo Workflow Service to accept it before answering 202
// anyway. A Send succeeding says nothing: rejections such as an exhausted
// quota only arrive on Recv, and they arrive well within this.
const defaultDetachedAcceptTimeout = 10 * time.Second

// defaultMaxDetachedRuns caps the detached runs one workhorse process holds at
// once. Nothing else bounds them per process: a detached run costs its caller
// no open connection, so the per-user rate limit admits about 50 a minute, each
// lasting up to the run limit.
const defaultMaxDetachedRuns = 100

var (
	// errDraining refuses a detached run once this workhorse instance is draining.
	errDraining = errors.New("workhorse is shutting down")
	// errTooManyDetachedRuns refuses a detached run once this process holds
	// maxDetachedRuns of them.
	errTooManyDetachedRuns = errors.New("too many detached workflow runs")
)

// handleDetachedConnection starts the run and answers 202 once Duo Workflow
// Service has accepted it, leaving the run going after the request ends. A
// failure before that is reported as a status code, as on the streaming path.
func (h *Handler) handleDetachedConnection(w http.ResponseWriter, r *http.Request, cfg *api.DuoWorkflow, startEvent *pb.ClientEvent) {
	// Saves opening a stream to Duo Workflow Service. Registering the runner
	// checks again, which is what closes the race with Shutdown.
	if h.isDraining() {
		fail.Request(w, r, errDraining, fail.WithStatus(http.StatusServiceUnavailable))
		return
	}

	// Before opening a stream to Duo Workflow Service, so a refused run costs it nothing.
	if !h.reserveDetachedRun() {
		detachedRunsRejectedTotal.Inc()
		fail.Request(w, r, errTooManyDetachedRuns, fail.WithStatus(http.StatusServiceUnavailable))
		return
	}

	// The run outlives the request, so it gets a copy whose context keeps the
	// request's values, such as the correlation ID, but is not canceled when
	// the request ends.
	runReq := r.Clone(context.WithoutCancel(r.Context()))
	runReq.Body = http.NoBody

	transport := newDetachedTransport(startEvent, h.runLimit())

	runner, err := h.createServerSideRunner(transport, cfg, runReq)
	if err != nil {
		h.releaseDetachedRun()
		logConnectionError(r, transportDetached, errorStageInitialization, err)
		fail.Request(w, r, fmt.Errorf("failed to initialize agent platform client: %v", err), fail.WithStatus(http.StatusBadGateway))
		return
	}
	// Once the dispatching job has its 202, the lock is the only thing that
	// keeps a retried or repeated dispatch from starting a second run.
	runner.lease.required = true

	startSent := make(chan struct{})
	runner.onStartSent = func() { close(startSent) }
	accepted := make(chan struct{})
	runner.onFirstAction = func() { close(accepted) }

	ended := make(chan error, 1)
	go h.runDetached(runReq, cfg, transport, runner, ended)

	// Taking the lock comes before sending the start request, so the accept
	// timeout does not count against a slow Redis.
	select {
	case <-startSent:
	case execErr := <-ended:
		h.reportDetachedEnd(w, r, cfg, transport, execErr)
		return
	case <-r.Context().Done():
		return
	}

	timer := time.NewTimer(h.acceptTimeout())
	defer timer.Stop()

	select {
	case <-accepted:
	case <-timer.C:
		if transport.WentAway() {
			h.reportDetachedEnd(w, r, cfg, transport, nil)
			return
		}
	case execErr := <-ended:
		h.reportDetachedEnd(w, r, cfg, transport, execErr)
		return
	case <-r.Context().Done():
		// Nobody is left to answer, and the run does not depend on the caller.
		return
	}

	acceptDetached(w, r, cfg)
}

// runDetached runs the workflow to its end and sends the outcome on ended:
// the execution error as soon as the runner reports it, before the runner is
// closed, or nil once the run is over. Nobody reads ended once the run is
// accepted, so a failure is logged here too.
func (h *Handler) runDetached(r *http.Request, cfg *api.DuoWorkflow, transport *detachedTransport, runner *runner, ended chan<- error) {
	defer h.releaseDetachedRun()

	reported := false
	report := func(err error) {
		reported = true
		logDetachedFailure(r, cfg, transport, err)
		ended <- err
	}

	// Only covers this goroutine, as net/http does for the streaming path; a
	// panic on one of the runner's own goroutines still takes the process down.
	defer func() {
		if p := recover(); p != nil {
			if !reported {
				report(fmt.Errorf("detached run panicked: %v", p))
			}
			return
		}

		if !reported {
			ended <- nil
		}
	}()

	h.registerAndExecuteRunner(r, transportDetached, runner, report)
}

func logDetachedFailure(r *http.Request, cfg *api.DuoWorkflow, transport *detachedTransport, err error) {
	if errors.Is(err, errDraining) || (transport.WentAway() && errors.Is(err, errTransportClosed)) {
		// Refused by a workhorse drain, which the 503 already logs, or ended by
		// one, which Shutdown logs.
		return
	}

	errorType, _, _ := classifyHTTPOutcome(transport, err)
	if errorType == "" {
		errorType = errorTypeOther
	}

	log.WithRequest(r).WithError(err).WithFields(log.Fields{
		"transport":   transportDetached,
		"workflow_id": cfg.WorkflowID,
		"error_type":  errorType,
	}).Error("duo workflow: detached run failed")
}

// reportDetachedEnd answers for a run that ended before it was accepted.
func (h *Handler) reportDetachedEnd(w http.ResponseWriter, r *http.Request, cfg *api.DuoWorkflow, transport *detachedTransport, execErr error) {
	if errors.Is(execErr, errDraining) {
		// Nothing was started, so the caller can dispatch it again elsewhere.
		fail.Request(w, r, execErr, fail.WithStatus(http.StatusServiceUnavailable))
		return
	}

	if transport.WentAway() && (execErr == nil || errors.Is(execErr, errTransportClosed)) {
		// Drained before it got going. A 202 would leave the caller believing
		// the run is underway.
		fail.Request(w, r, errors.New("workflow run was interrupted before it started"), fail.WithStatus(http.StatusServiceUnavailable))
		return
	}

	errorType, status, message := classifyHTTPOutcome(transport, execErr)
	if errorType == "" {
		// Duo Workflow Service ended the run cleanly.
		acceptDetached(w, r, cfg)
		return
	}

	fail.Request(w, r, errors.New(message), fail.WithStatus(status))
}

func acceptDetached(w http.ResponseWriter, r *http.Request, cfg *api.DuoWorkflow) {
	log.WithRequest(r).WithFields(log.Fields{"workflow_id": cfg.WorkflowID}).Info("duo workflow: detached run accepted")
	w.WriteHeader(http.StatusAccepted)
}

// reserveDetachedRun takes one of the process's detached run slots, if one is
// free. The caller must release it with releaseDetachedRun once the run is over.
func (h *Handler) reserveDetachedRun() bool {
	h.runnersMu.Lock()
	defer h.runnersMu.Unlock()

	if h.detachedRuns >= h.maxDetached() {
		return false
	}

	h.detachedRuns++
	return true
}

func (h *Handler) releaseDetachedRun() {
	h.runnersMu.Lock()
	defer h.runnersMu.Unlock()

	h.detachedRuns--
}

func (h *Handler) maxDetached() int {
	if h.maxDetachedRuns == 0 {
		return defaultMaxDetachedRuns
	}
	return h.maxDetachedRuns
}

func (h *Handler) runLimit() time.Duration {
	if h.detachedRunLimit == 0 {
		return defaultDetachedRunLimit
	}
	return h.detachedRunLimit
}

func (h *Handler) acceptTimeout() time.Duration {
	if h.detachedAcceptTimeout == 0 {
		return defaultDetachedAcceptTimeout
	}
	return h.detachedAcceptTimeout
}
