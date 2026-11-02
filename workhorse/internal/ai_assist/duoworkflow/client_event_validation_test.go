package duoworkflow

import (
	"context"
	"fmt"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/require"
	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"
)

const invalidEventLogPrefix = "handleClientEvent: received a client event that is not valid"

func newValidationRunner(t *testing.T, reject bool) (*runner, *mockWorkflowStream) {
	t.Helper()

	wf := &mockWorkflowStream{}
	sess := newSession(httptest.NewRequest("GET", "/duo", nil))

	return &runner{
		session:                   sess,
		client:                    newWsManager(&mockWebSocketConn{}),
		httpActionHandler:         &runHTTPActionHandler{session: sess},
		streamManager:             &streamManager{wf: wf, session: sess},
		mcpManager:                &mockMcpManager{},
		lease:                     newWorkflowLease(nil),
		rejectInvalidClientEvents: reject,
	}, wf
}

func testStartRequestEvent() *pb.ClientEvent {
	return &pb.ClientEvent{Response: &pb.ClientEvent_StartRequest{
		StartRequest: &pb.StartWorkflowRequest{WorkflowID: "wf-1", Goal: "goal"},
	}}
}

func heartbeatEvent() *pb.ClientEvent {
	return &pb.ClientEvent{Response: &pb.ClientEvent_Heartbeat{Heartbeat: &pb.HeartbeatRequest{}}}
}

func actionResponseEvent(requestID string) *pb.ClientEvent {
	return &pb.ClientEvent{Response: &pb.ClientEvent_ActionResponse{
		ActionResponse: &pb.ActionResponse{RequestID: requestID},
	}}
}

func readFileAction(requestID string) *pb.Action {
	return &pb.Action{
		RequestID: requestID,
		Action:    &pb.Action_RunReadFile{RunReadFile: &pb.ReadFile{Filepath: "a.go"}},
	}
}

func TestRunner_InvalidClientEvent(t *testing.T) {
	tests := []struct {
		name   string
		reject bool
		mode   string
	}{
		{name: "log only", reject: false, mode: invalidEventModeLogOnly},
		{name: "enforced", reject: true, mode: invalidEventModeEnforced},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hook := newLogHook(t)
			r, wf := newValidationRunner(t, tt.reject)

			err := r.handleClientEvent(heartbeatEvent())

			entries := entriesWithPrefix(hook, invalidEventLogPrefix)
			require.Len(t, entries, 1)
			require.Equal(t, "heartbeat", entries[0].Data["event_type"])
			require.Equal(t, invalidEventBeforeStart, entries[0].Data["invalid_event_reason"])
			require.Equal(t, tt.mode, entries[0].Data["mode"])

			if tt.reject {
				require.ErrorIs(t, err, errInvalidClientEvent)
				require.Empty(t, wf.getSendEvents(), "a rejected event must not reach DWS")
				require.Equal(t, teardownClientInvalidEvent, r.teardown.load())
			} else {
				require.NoError(t, err)
				require.Len(t, wf.getSendEvents(), 1, "log-only mode forwards the event as before")
				require.Equal(t, teardownUnsolicited, r.teardown.load())
			}
		})
	}
}

func TestRunner_InvalidClientEvent_LogsOncePerReason(t *testing.T) {
	hook := newLogHook(t)
	r, wf := newValidationRunner(t, false)

	require.NoError(t, r.handleClientEvent(heartbeatEvent()))
	require.NoError(t, r.handleClientEvent(actionResponseEvent("forged")))
	require.NoError(t, r.handleClientEvent(testStartRequestEvent()))
	require.NoError(t, r.handleClientEvent(actionResponseEvent("forged-1")))
	require.NoError(t, r.handleClientEvent(actionResponseEvent("forged-2")))

	require.Len(t, wf.getSendEvents(), 5)

	entries := entriesWithPrefix(hook, invalidEventLogPrefix)
	require.Len(t, entries, 2)
	require.Equal(t, invalidEventBeforeStart, entries[0].Data["invalid_event_reason"])
	require.Equal(t, invalidEventUnknownRequestID, entries[1].Data["invalid_event_reason"])
	for _, e := range entries {
		require.NotContains(t, e.Data, "request_id", "the client chooses the request ID, so it is not logged")
	}
}

func TestRunner_ActionResponseValidation(t *testing.T) {
	ctx := context.Background()

	r, wf := newValidationRunner(t, true)
	d := r.actionDispatcher()

	require.NoError(t, r.handleClientEvent(testStartRequestEvent()))
	require.NoError(t, d.dispatch(ctx, readFileAction("req-1")))
	require.NoError(t, d.dispatch(ctx, &pb.Action{
		RequestID: "req-checkpoint",
		Action:    &pb.Action_NewCheckpoint{NewCheckpoint: &pb.NewCheckpoint{}},
	}))

	require.NoError(t, r.handleClientEvent(heartbeatEvent()), "a heartbeat is valid after the start request")
	require.NoError(t, r.handleClientEvent(actionResponseEvent("req-1")))

	tests := []struct {
		name      string
		requestID string
		reason    string
	}{
		{name: "already answered", requestID: "req-1", reason: invalidEventUnknownRequestID},
		{name: "never sent", requestID: "req-forged", reason: invalidEventUnknownRequestID},
		{name: "checkpoint, which needs no answer", requestID: "req-checkpoint", reason: invalidEventUnknownRequestID},
		{name: "no request ID", requestID: "", reason: invalidEventMissingRequestID},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := r.handleClientEvent(actionResponseEvent(tt.requestID))

			var invalidErr *invalidClientEventError
			require.ErrorAs(t, err, &invalidErr)
			require.Equal(t, tt.reason, invalidErr.reason)
		})
	}

	// The start request, the heartbeat and the one valid response.
	require.Len(t, wf.getSendEvents(), 3)
}

func TestActionDispatcher_UnsupportedActionIsNotPending(t *testing.T) {
	wf := &mockWorkflowStream{}
	d := newTestDispatcher(t, wf, newDetachedTransport(nil, time.Hour), &mockMcpManager{}, nil)

	require.NoError(t, d.dispatch(context.Background(), readFileAction("req-1")))

	require.Len(t, wf.getSendEvents(), 1, "Workhorse answers an action the client can't run")
	require.False(t, d.pending.answer("req-1"), "so the client must not answer it too")
}

func TestRunner_Execute_RejectsEventBeforeStart(t *testing.T) {
	mockConn := &mockWebSocketConn{
		readMessages: [][]byte{
			[]byte(`{"actionResponse": {"requestID": "forged"}}`),
			[]byte(`{"startRequest": {"goal": "test", "workflowID": "wf-1"}}`),
		},
	}
	mockWf := &mockWorkflowStream{blockCh: make(chan bool)}

	r, _ := newValidationRunner(t, true)
	r.client = newWsManager(mockConn)
	r.streamManager.wf = mockWf

	err := r.Execute(context.Background())
	require.ErrorIs(t, err, errInvalidClientEvent)
	require.Empty(t, mockWf.getSendEvents())
}

func TestHandler_InvalidClientEventClosesWithPolicyViolation(t *testing.T) {
	controlMessages := []struct {
		msgType int
		data    []byte
	}{}
	ws := newWsManager(&shutdownTrackingConn{
		mockWebSocketConn: &mockWebSocketConn{},
		controlMessages:   &controlMessages,
	})

	err := fmt.Errorf("wrapped: %w", &invalidClientEventError{reason: invalidEventUnknownRequestID})
	(&Handler{}).handleWebSocketExecutionError(httptest.NewRequest("GET", "/duo", nil), ws, err)

	require.Len(t, controlMessages, 1)
	require.Equal(t, websocket.CloseMessage, controlMessages[0].msgType)
	expected := websocket.FormatCloseMessage(websocket.ClosePolicyViolation, "Invalid client event: unknown_request_id")
	require.Equal(t, expected, controlMessages[0].data)
}
