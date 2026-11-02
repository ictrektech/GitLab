package duoworkflow

import (
	"context"
	"errors"
	"sync/atomic"
	"time"

	redis "github.com/redis/go-redis/v9"
)

const (
	// stopSignalPrefix keys the signal Rails sets when a workflow is stopped.
	// It must match Gitlab::DuoWorkflow::WorkhorseStopSignal::KEY_PREFIX.
	stopSignalPrefix = "workhorse:duoworkflow:stop:"

	// defaultStopSignalInterval is how often a server-side run checks for the
	// signal while no action is being executed.
	defaultStopSignalInterval = 5 * time.Second

	stopSignalCheckTimeout = time.Second
)

// errStopRequested answers an action received after the workflow was stopped,
// and is the close error logged with the StopWorkflowRequest.
var errStopRequested = errors.New("the workflow was stopped in GitLab")

// stopSignal is how Rails stops a server-side run. A WebSocket client stops its
// run by closing the connection, but the caller of the server-side execution
// endpoint sends nothing once the run has started, and a detached run has no
// caller at all. Rails sets a Redis key instead when the workflow is stopped,
// and the run checks it on a ticker and before each action Workhorse executes.
type stopSignal struct {
	rdb      *redis.Client
	interval time.Duration

	// seen latches the signal, so nothing asks Redis again once it is set.
	seen atomic.Bool

	// wake asks the watcher to check now, once an action has found the
	// signal set, instead of on its next tick.
	wake chan struct{}
}

func newStopSignal(rdb *redis.Client, interval time.Duration) *stopSignal {
	if rdb == nil {
		return nil
	}

	return &stopSignal{
		rdb:      rdb,
		interval: interval,
		wake:     make(chan struct{}, 1),
	}
}

// requested reports whether Rails stopped the session's workflow. A Redis
// failure is logged and reported as no signal, so the run carries on as it
// would without one.
func (s *stopSignal) requested(ctx context.Context, sess *session) bool {
	if s.seen.Load() {
		return true
	}

	workflowID := sess.WorkflowID()
	if workflowID == "" {
		return false
	}

	ctx, cancel := context.WithTimeout(ctx, stopSignalCheckTimeout)
	defer cancel()

	n, err := s.rdb.Exists(ctx, stopSignalPrefix+workflowID).Result()
	if err != nil {
		// Not when the run is ending, which cancels the check.
		if !errors.Is(ctx.Err(), context.Canceled) {
			sess.logger().WithError(err).Error("stopSignal: failed to check for a stop signal")
		}
		return false
	}

	if n == 0 {
		return false
	}

	s.seen.Store(true)
	return true
}

// notify wakes the watcher without waiting for it.
func (s *stopSignal) notify() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}
