package duoworkflow

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"
)

// defaultDetachedRunLimit bounds a detached run, which has no caller who can
// hang up. It stays below the one-hour cap on a Duo Workflow Service stream
// and the two-hour lifetime of the user token and the workflow lock.
const defaultDetachedRunLimit = 55 * time.Minute

// errRunLimitReached is returned by ReadClientEvent when a detached run
// reaches its time limit.
var errRunLimitReached = errors.New("detachedTransport: run limit reached")

// detachedTransport is the clientTransport for a run that outlives the request
// that started it. Like ndjsonTransport, it reports the StartWorkflowRequest
// as the only client event and executes no action itself, but nobody is
// reading the actions, so checkpoints are dropped as well.
//
// The run ends when Duo Workflow Service ends the stream, when this workhorse
// instance drains, or when the run limit is reached, which asks Duo Workflow
// Service to stop the workflow with reasonRunLimit.
type detachedTransport struct {
	startEvent *pb.ClientEvent
	runLimit   time.Duration

	// timer is armed by Start, once the stream to Duo Workflow Service and
	// the MCP servers are set up.
	timer *time.Timer

	closed    chan struct{}
	closeOnce sync.Once

	// wentAway records that the run was interrupted, by a drain on either
	// side, rather than finished.
	wentAway atomic.Bool

	invalidRequestMu     sync.Mutex
	invalidRequestReason string

	startRead bool
}

func newDetachedTransport(startEvent *pb.ClientEvent, runLimit time.Duration) *detachedTransport {
	return &detachedTransport{
		startEvent: startEvent,
		runLimit:   runLimit,
		closed:     make(chan struct{}),
	}
}

// Start arms the run limit.
func (t *detachedTransport) Start() error {
	t.timer = time.NewTimer(t.runLimit)

	return nil
}

// KeepaliveInterval returns 0: there is no connection to keep alive.
func (t *detachedTransport) KeepaliveInterval() time.Duration { return 0 }

// Keepalive is never called, because KeepaliveInterval is 0.
func (t *detachedTransport) Keepalive() error { return nil }

// ReadClientEvent reports the StartWorkflowRequest, then blocks until the run
// limit is reached or the transport is closed.
func (t *detachedTransport) ReadClientEvent() (*pb.ClientEvent, error) {
	if !t.startRead {
		t.startRead = true
		return t.startEvent, nil
	}

	select {
	case <-t.timer.C:
		return nil, errRunLimitReached
	case <-t.closed:
		return nil, errTransportClosed
	}
}

// ReadError asks for a StopWorkflowRequest only when the run limit is reached.
// Duo Workflow Service keeps the workflow running for an infrastructure stop
// reason, so it can be resumed from its last checkpoint.
func (t *detachedTransport) ReadError(err error) (reason string, ok bool) {
	if errors.Is(err, errRunLimitReached) {
		return reasonRunLimit, true
	}

	return "", false
}

// WriteAction drops checkpoints, which Duo Workflow Service also persists
// through the API, and rejects every other action with errActionUnsupported.
func (t *detachedTransport) WriteAction(_ context.Context, action *pb.Action) error {
	if _, ok := action.Action.(*pb.Action_NewCheckpoint); ok {
		return nil
	}

	return fmt.Errorf("%w: %T", errActionUnsupported, action.Action)
}

// SendGoingAway has nobody to tell, so it records the interruption. Rails
// learns the outcome from the workflow's status.
//
// On a workhorse drain it also ends the run, as closing the connection does
// on the WebSocket path: the run's context is never canceled, so a run whose
// stop request went unacknowledged would otherwise outlive its released lock.
// A drain of Duo Workflow Service ends the run on its own.
func (t *detachedTransport) SendGoingAway(reason string) error {
	t.wentAway.Store(true)

	if reason == closeReasonWorkhorseShutdown {
		return t.Close()
	}

	return nil
}

// WentAway reports whether the run was interrupted by a drain.
func (t *detachedTransport) WentAway() bool {
	return t.wentAway.Load()
}

// SendInvalidRequest records the reason, so the handler can still report it
// as a 400 when Duo Workflow Service rejects the start request itself.
func (t *detachedTransport) SendInvalidRequest(reason string) error {
	t.invalidRequestMu.Lock()
	defer t.invalidRequestMu.Unlock()

	t.invalidRequestReason = reason

	return nil
}

// InvalidRequestReason returns the reason Duo Workflow Service gave for
// rejecting the request as invalid, or an empty string if it did not.
func (t *detachedTransport) InvalidRequestReason() string {
	t.invalidRequestMu.Lock()
	defer t.invalidRequestMu.Unlock()

	return t.invalidRequestReason
}

// Close releases a pending ReadClientEvent and stops the run limit timer.
func (t *detachedTransport) Close() error {
	t.closeOnce.Do(func() {
		close(t.closed)
		if t.timer != nil {
			t.timer.Stop()
		}
	})

	return nil
}
