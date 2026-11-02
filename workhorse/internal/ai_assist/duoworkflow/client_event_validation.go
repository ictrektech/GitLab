package duoworkflow

import (
	"errors"
	"fmt"
	"sync"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/log"
)

var errInvalidClientEvent = errors.New("handleClientEvent: the client sent an event that is not valid in the current state of the run")

// Values of the invalid_event_reason field of the log entry and of the close reason.
const (
	invalidEventBeforeStart      = "before_start"
	invalidEventMissingRequestID = "missing_request_id"
	invalidEventUnknownRequestID = "unknown_request_id"
)

// Values of the mode field of the log entry.
const (
	invalidEventModeEnforced = "enforced"
	invalidEventModeLogOnly  = "log_only"
)

// pendingActions holds the request IDs of the actions written to the client
// that it has not answered yet. The goroutine receiving actions adds to it and
// the one reading client events removes from it.
type pendingActions struct {
	mu  sync.Mutex
	ids map[string]struct{}
}

func (p *pendingActions) add(requestID string) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.ids == nil {
		p.ids = make(map[string]struct{})
	}
	p.ids[requestID] = struct{}{}
}

// answer removes requestID and reports whether it was waiting for an answer.
func (p *pendingActions) answer(requestID string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()

	if _, ok := p.ids[requestID]; !ok {
		return false
	}
	delete(p.ids, requestID)
	return true
}

// expectsResponse mirrors ACTION_TYPES_WITHOUT_RESPONSES in the Duo Workflow
// Service outbox: tracking checkpoints would grow the set for the whole run.
func expectsResponse(action *pb.Action) bool {
	_, isCheckpoint := action.Action.(*pb.Action_NewCheckpoint)
	return !isCheckpoint && action.GetRequestID() != ""
}

// invalidClientEventReason returns why the event is not valid in the current
// state of the run, or "" when it is. An action response it accepts is no
// longer pending.
func (r *runner) invalidClientEventReason(event *pb.ClientEvent) string {
	if event.GetStartRequest() != nil {
		return ""
	}

	if !r.started {
		return invalidEventBeforeStart
	}

	actionResponse := event.GetActionResponse()
	if actionResponse == nil {
		return ""
	}

	requestID := actionResponse.GetRequestID()
	if requestID == "" {
		return invalidEventMissingRequestID
	}
	if !r.pending.answer(requestID) {
		return invalidEventUnknownRequestID
	}

	return ""
}

// checkClientEvent reports an invalid event, and rejects it only when
// enforcement is on. Each reason is logged once per connection, without the
// payload or the client-chosen request ID, so a looping client can't flood
// the logs.
func (r *runner) checkClientEvent(event *pb.ClientEvent) error {
	reason := r.invalidClientEventReason(event)
	if reason == "" {
		return nil
	}

	mode := invalidEventModeLogOnly
	if r.rejectInvalidClientEvents {
		mode = invalidEventModeEnforced
	}

	if !r.invalidEventsLogged[reason] {
		if r.invalidEventsLogged == nil {
			r.invalidEventsLogged = make(map[string]bool)
		}
		r.invalidEventsLogged[reason] = true

		r.session.logger().WithFields(log.Fields{
			"event_type":           clientEventName(event),
			"invalid_event_reason": reason,
			"mode":                 mode,
		}).Warn("handleClientEvent: received a client event that is not valid in the current state of the run")
	}

	if !r.rejectInvalidClientEvents {
		return nil
	}

	r.teardown.record(teardownClientInvalidEvent)
	return &invalidClientEventError{reason: reason}
}

type invalidClientEventError struct {
	reason string
}

func (e *invalidClientEventError) Error() string {
	return fmt.Sprintf("%v: %s", errInvalidClientEvent, e.reason)
}

func (e *invalidClientEventError) Unwrap() error { return errInvalidClientEvent }

// closeReason is sent to the client in the close frame.
func (e *invalidClientEventError) closeReason() string {
	return "Invalid client event: " + e.reason
}

// clientEventName is the name of the event's oneof field, such as actionResponse.
func clientEventName(event *pb.ClientEvent) string {
	m := event.ProtoReflect()
	if fd := m.WhichOneof(m.Descriptor().Oneofs().ByName("response")); fd != nil {
		return string(fd.Name())
	}
	return "none"
}
