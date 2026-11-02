package duoworkflow

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"sync"
	"time"

	redis "github.com/redis/go-redis/v9"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/api"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/helper/fail"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/helper/shutdown"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/log"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/origincheck"

	"github.com/gorilla/websocket"
)

// Handler manages Duo Workflow WebSocket connections and provides graceful shutdown
// for active workflow runners. It tracks all active runners to ensure they can be
// properly terminated during server shutdown.
type Handler struct {
	rails                 *api.API
	rdb                   *redis.Client
	backend               http.Handler
	relativeURLRoot       string
	upgrader              websocket.Upgrader
	runners               sync.Map // map[*runner]bool
	runnersMu             sync.Mutex
	draining              bool
	detachedRuns          int // guarded by runnersMu
	stopWorkflowTimeout   time.Duration
	trustedForwardedHosts []string

	// Zero selects defaultDetachedRunLimit, defaultDetachedAcceptTimeout and
	// defaultMaxDetachedRuns.
	detachedRunLimit      time.Duration
	detachedAcceptTimeout time.Duration
	maxDetachedRuns       int

	// Zero selects defaultStopSignalInterval.
	stopSignalInterval time.Duration
}

// NewHandler creates a new Handler for managing Duo Workflow WebSocket connections.
// The handler maintains a registry of active runners to support graceful shutdown
// of WebSocket connections during server termination.
//
// relativeURLRoot is GitLab's URL prefix (e.g. "/gitlab/"), empty at the domain
// root. It is forwarded to the action handler so DWS action paths resolve
// against the correct prefix when re-entering the upstream router.
func NewHandler(rails *api.API, rdb *redis.Client, backend http.Handler, relativeURLRoot string, trustedForwardedHosts ...string) *Handler {
	return &Handler{
		rails:                 rails,
		backend:               backend,
		relativeURLRoot:       relativeURLRoot,
		rdb:                   rdb,
		upgrader:              websocket.Upgrader{},
		trustedForwardedHosts: trustedForwardedHosts,
	}
}

// Shutdown gracefully terminates all active workflow runners within the provided context timeout.
// It collects all active runners and initiates shutdown concurrently for all of them.
func (h *Handler) Shutdown(ctx context.Context) error {
	// Under the lock so that no runner can register between this and the
	// Range below, and be missed by both.
	h.runnersMu.Lock()
	h.draining = true
	h.runnersMu.Unlock()

	var runners []shutdown.GracefulCloser

	h.runners.Range(func(key, _ interface{}) bool {
		if r, ok := key.(*runner); ok {
			runners = append(runners, r)
		}
		return true
	})

	return shutdown.All(ctx, runners...)
}

const (
	errorTypeQuotaExceeded = "quota_exceeded"
	errorTypeLocked        = "locked"
	errorTypeOther         = "other"
)

// The transport the client used to reach the handler. All are reported under
// the same metrics, because the flow they run is the same and the difference
// that matters is who executes the actions.
const (
	transportWebSocket = "websocket"
	transportHTTP      = "http"
	transportDetached  = "detached"
)

// Stages at which a connection can fail with errorTypeOther. Logged so the
// otherwise opaque "other" error type can be traced back to a specific stage.
const (
	errorStageUpgrade        = "websocket_upgrade"
	errorStageRequestBody    = "request_body"
	errorStageInitialization = "runner_initialization"
	errorStageExecution      = "runner_execution"
)

// logConnectionError logs a connection failure that has no more specific error
// type than "other", along with the stage it failed at.
func logConnectionError(r *http.Request, transport string, stage string, err error) {
	log.WithRequest(r).WithError(err).WithFields(log.Fields{
		"transport":   transport,
		"error_stage": stage,
		"error_type":  errorTypeOther,
	}).Error("duo workflow connection failed")
}

// Build returns an HTTP handler that processes Duo Workflow WebSocket connections.
// The handler performs pre-authorization checks, upgrades the connection to WebSocket,
// and manages the lifecycle of the workflow runner including registration and cleanup.
func (h *Handler) Build() http.Handler {
	return h.rails.PreAuthorizeHandler(func(w http.ResponseWriter, r *http.Request, a *api.Response) {
		upgrader := h.upgrader
		if len(h.trustedForwardedHosts) > 0 {
			upgrader.CheckOrigin = origincheck.ByForwardedHost(h.trustedForwardedHosts)
		}

		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			logConnectionError(r, transportWebSocket, errorStageUpgrade, err)
			fail.Request(w, r, fmt.Errorf("failed to upgrade: %v", err))
			return
		}

		conn.SetReadLimit(MaxMessageSize)

		h.handleWebSocketConnection(r, conn, a.DuoWorkflow)
	}, "")
}

func (h *Handler) handleWebSocketConnection(r *http.Request, conn *websocket.Conn, duoWorkflowConfig *api.DuoWorkflow) {
	ws := newWsManager(conn)

	runner, err := h.createRunner(ws, duoWorkflowConfig, r)
	if err != nil {
		logConnectionError(r, transportWebSocket, errorStageInitialization, err)
		h.handleInitializationError(r, ws)
		return
	}

	h.registerAndExecuteRunner(r, transportWebSocket, runner, func(err error) {
		h.handleWebSocketExecutionError(r, ws, err)
	})
}

func (h *Handler) createRunner(client clientTransport, duoWorkflowConfig *api.DuoWorkflow, r *http.Request) (*runner, error) {
	runner, err := newRunner(client, h.rails, h.backend, h.relativeURLRoot, r, duoWorkflowConfig, h.rdb)
	if err != nil {
		return nil, err
	}
	runner.stopWorkflowTimeout = h.stopWorkflowTimeout
	return runner, nil
}

// createServerSideRunner watches for the stop signal Rails sets, so Rails can
// stop a server-side run, whose caller cannot send a stop of its own. Without
// Redis there is nothing to watch.
func (h *Handler) createServerSideRunner(client clientTransport, duoWorkflowConfig *api.DuoWorkflow, r *http.Request) (*runner, error) {
	runner, err := h.createRunner(client, duoWorkflowConfig, r)
	if err != nil {
		return nil, err
	}

	interval := h.stopSignalInterval
	if interval == 0 {
		interval = defaultStopSignalInterval
	}

	runner.stopSignal = newStopSignal(h.rdb, interval)
	return runner, nil
}

// handleInitializationError reports the failure with a close frame: the
// connection is already upgraded, so an HTTP error response can't be written.
func (h *Handler) handleInitializationError(r *http.Request, ws *wsManager) {
	h.sendCloseMessage(r, ws, websocket.CloseInternalServerErr, "Failed to initialize agent platform client")
	if closeErr := ws.Close(); closeErr != nil {
		log.WithRequest(r).WithError(closeErr).Error("failed to close connection")
	}
}

// registerAndExecuteRunner tracks the runner for the duration of the workflow
// so that a server shutdown can stop it gracefully.
//
// reportError is called with a non-nil execution error while the connection is
// still open, before the runner is closed, so that a transport can still tell
// its client what went wrong.
func (h *Handler) registerAndExecuteRunner(r *http.Request, transport string, runner *runner, reportError func(error)) {
	openConnections := connectionsOpen.WithLabelValues(transport)

	start := time.Now()

	if !h.register(runner, transport) {
		reportError(errDraining)
		_ = runner.Close()
		return
	}
	openConnections.Inc()
	defer func() {
		defer openConnections.Dec()
		h.runners.Delete(runner)
		_ = runner.Close()
		// After Close, which waits for Shutdown to record its teardown reason.
		sessionDurationSeconds.WithLabelValues(transport, runner.teardown.load().String()).Observe(time.Since(start).Seconds())
	}()

	if err := runner.Execute(runner.session.Context()); err != nil {
		log.WithRequest(r).WithError(err).WithFields(log.Fields{
			"duration_ms": time.Since(start).Milliseconds(),
		}).Error("error executing workflow")

		reportError(err)
	}
}

// register tracks the runner unless a drain has started and the run is
// detached. A detached run outlives its request, so once Shutdown has
// collected the runners to stop, nothing would stop it before the process
// exits, and its workflow lock would stay held until it expires.
func (h *Handler) register(runner *runner, transport string) bool {
	h.runnersMu.Lock()
	defer h.runnersMu.Unlock()

	if h.draining && transport == transportDetached {
		return false
	}

	h.runners.Store(runner, true)
	return true
}

func (h *Handler) isDraining() bool {
	h.runnersMu.Lock()
	defer h.runnersMu.Unlock()

	return h.draining
}

func (h *Handler) handleWebSocketExecutionError(r *http.Request, ws *wsManager, err error) {
	switch {
	case errors.Is(err, errFailedToAcquireLock):
		// We provide the client with specific error details
		// for this case so it can tell the user about the
		// conflicting flow
		h.sendCloseMessage(r, ws, websocket.CloseTryAgainLater, "Failed to acquire lock on workflow")
	case errors.Is(err, errUsageQuotaExceededError):
		// We close the connection with the specific error
		// so client can process and inform user about the lack
		// of credits
		h.sendCloseMessage(r, ws, websocket.ClosePolicyViolation, "Insufficient credits: quota exceeded")
	case errors.Is(err, errInvalidClientEvent):
		reason := "Invalid client event"
		var invalidErr *invalidClientEventError
		if errors.As(err, &invalidErr) {
			reason = invalidErr.closeReason()
		}
		h.sendCloseMessage(r, ws, websocket.ClosePolicyViolation, reason)
	case errors.Is(err, errPermissionDenied):
		// DWS refused to run the session; forward its reason so the client sees the denial,
		// not a 1000 "normal finish". errors.Is also matches a bare errPermissionDenied, so
		// this static reason covers that case and errors.As overrides it with Recv's message.
		reason := "Permission denied"
		var permErr *permissionDeniedError
		if errors.As(err, &permErr) {
			reason = permErr.msg
		}
		h.sendCloseMessage(r, ws, closePermissionDenied, reason)
	default:
		logConnectionError(r, transportWebSocket, errorStageExecution, err)
	}
}

func (h *Handler) sendCloseMessage(r *http.Request, ws *wsManager, code int, reason string) {
	if err := ws.SendClose(code, reason); err != nil {
		log.WithRequest(r).WithError(err).Error("failed to send close message")
	}
}
