package duoworkflow

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	redis "github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"
)

// signalStop sets the stop signal the way Rails does when the workflow is stopped.
func signalStop(rdb *redis.Client) error {
	return rdb.Set(context.Background(), stopSignalPrefix+testWorkflowID, "1", time.Minute).Err()
}

func setStopSignal(t *testing.T, rdb *redis.Client) {
	t.Helper()

	require.NoError(t, signalStop(rdb))
}

func TestNewStopSignal_disabledWithoutRedis(t *testing.T) {
	require.Nil(t, newStopSignal(nil, time.Second))
}

func TestStopSignal_requested(t *testing.T) {
	ctx := context.Background()

	newTestSession := func(workflowID string) *session {
		sess := newSession(httptest.NewRequest(http.MethodPost, "/execute", nil))
		sess.setWorkflowID(workflowID)
		t.Cleanup(sess.Close)

		return sess
	}

	t.Run("is not requested before the workflow is known", func(t *testing.T) {
		rdb := initRdb(t)
		setStopSignal(t, rdb)

		require.False(t, newStopSignal(rdb, time.Second).requested(ctx, newTestSession("")))
	})

	t.Run("is not requested without a signal", func(t *testing.T) {
		require.False(t, newStopSignal(initRdb(t), time.Second).requested(ctx, newTestSession(testWorkflowID)))
	})

	t.Run("is requested once Rails sets the signal, and stays requested", func(t *testing.T) {
		rdb := initRdb(t)
		signal := newStopSignal(rdb, time.Second)
		sess := newTestSession(testWorkflowID)

		setStopSignal(t, rdb)
		require.True(t, signal.requested(ctx, sess))

		require.NoError(t, rdb.Del(ctx, stopSignalPrefix+testWorkflowID).Err())
		require.True(t, signal.requested(ctx, sess), "a seen signal does not need Redis anymore")
	})

	t.Run("is not requested when Redis is unavailable", func(t *testing.T) {
		require.False(t, newStopSignal(unreachableRedis(t), time.Second).requested(ctx, newTestSession(testWorkflowID)))
	})
}

func TestRunner_handleAgentMessages_acknowledgesAStopEndedWithEOF(t *testing.T) {
	sess := newSession(httptest.NewRequest(http.MethodPost, "/execute", nil))
	r := &runner{
		session:       sess,
		streamManager: &streamManager{wf: &mockWorkflowStream{recvError: io.EOF}, session: sess},
		stop:          stopCoordinator{acked: make(chan struct{})},
	}
	r.stop.requested.Store(true)

	errCh := make(chan error, 1)
	r.handleAgentMessages(context.Background(), errCh)

	require.NoError(t, <-errCh)
	require.NoError(t, r.stop.waitForAck(0), "DWS ends the stream with OK once it stopped the workflow for good")
}

// stopOnSignal is a Duo Workflow Service that accepts the start request, sends a
// checkpoint, has Rails signal a stop, and reports the reason of the stop
// request it receives. It ends the stream with OK, as it does for a stop that
// is not an infrastructure one.
func stopOnSignal(rdb *redis.Client, stopReasons chan<- string) func(pb.DuoWorkflow_ExecuteWorkflowServer) error {
	return func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		if err := signalStop(rdb); err != nil {
			return err
		}

		event, err := stream.Recv()
		if err != nil {
			return err
		}
		stopReasons <- event.GetStopWorkflow().GetReason()

		return nil
	}
}

func TestBuildHTTP_StoppedBySignal(t *testing.T) {
	stopReasons := make(chan string, 1)

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = stopOnSignal(initRdb(t), stopReasons)

	server := setupConfiguredExecuteHandler(t, grpcServer, func(h *Handler) {
		h.stopSignalInterval = 10 * time.Millisecond
	})

	resp := postStartRequest(t, server, `{"goal": "fix the pipeline"}`)
	require.Equal(t, http.StatusOK, resp.statusCode)
	require.Len(t, parseNdjsonActions(t, resp.body), 1)

	select {
	case reason := <-stopReasons:
		require.Equal(t, reasonStopRequested, reason)
	default:
		t.Fatal("the stream ended without a stop request")
	}
}

func TestBuildHTTP_Detached_StoppedBySignal(t *testing.T) {
	stopReasons := make(chan string, 1)

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = stopOnSignal(initRdb(t), stopReasons)

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.stopSignalInterval = 10 * time.Millisecond
	})

	acked := counterVecValue(t, stopRequestsTotal, stopOutcomeAcked)

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	select {
	case reason := <-stopReasons:
		require.Equal(t, reasonStopRequested, reason)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the signal to stop the workflow")
	}

	require.Eventually(t, func() bool { return !lockHeld(t, s.rdb) }, 5*time.Second, 10*time.Millisecond,
		"the lock is released once the run is stopped")
	require.Eventually(t, func() bool {
		return counterVecValue(t, stopRequestsTotal, stopOutcomeAcked) == acked+1
	}, 5*time.Second, 10*time.Millisecond, "the stream ending is the acknowledgment")
}

func TestBuildHTTP_Detached_SignaledStopSkipsTheNextAction(t *testing.T) {
	responses := make(chan *pb.ActionResponse, 1)
	stopReasons := make(chan string, 1)
	rdb := initRdb(t)

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		if err := signalStop(rdb); err != nil {
			return err
		}

		action := &pb.Action{
			RequestID: "req-http",
			Action: &pb.Action_RunHTTPRequest{
				RunHTTPRequest: &pb.RunHTTPRequest{Method: http.MethodPost, Path: "/api/v4/projects/1/merge_requests"},
			},
		}
		if err := stream.Send(action); err != nil {
			return err
		}

		event, err := stream.Recv()
		if err != nil {
			return err
		}
		responses <- event.GetActionResponse()

		event, err = stream.Recv()
		if err != nil {
			return err
		}
		stopReasons <- event.GetStopWorkflow().GetReason()

		return nil
	}

	var backendCalls atomic.Int32
	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		// Long enough that only the action finding the signal can stop the run in time.
		h.stopSignalInterval = time.Minute
		h.backend = http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) { backendCalls.Add(1) })
	})

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	select {
	case response := <-responses:
		require.Equal(t, "req-http", response.RequestID)
		require.Equal(t, errStopRequested.Error(), response.GetPlainTextResponse().GetError())
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the action to be answered")
	}

	select {
	case reason := <-stopReasons:
		require.Equal(t, reasonStopRequested, reason)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the signal to stop the workflow")
	}

	require.Zero(t, backendCalls.Load(), "the API call is not made once the workflow was stopped")
}
