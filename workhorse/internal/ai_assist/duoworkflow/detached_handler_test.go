package duoworkflow

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	redis "github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/testhelper"
)

// detachedSetup is a server-side execution endpoint with detached execution
// enabled in the pre-authorization response.
type detachedSetup struct {
	server  *httptest.Server
	handler *Handler
	rdb     *redis.Client
}

// setupDetachedHandler is setupExecuteHandler with detached execution enabled.
// configure can adjust the handler before it starts serving. Detached runs
// outlive their requests, so cleanup waits for them to end before Redis and
// the gRPC server go away.
func setupDetachedHandler(t *testing.T, grpcServer *testServer, lockConcurrentFlow bool, configure func(*Handler)) detachedSetup {
	t.Helper()

	testhelper.ConfigureSecret()

	apiServer, apiClient := setupAPIServer(t, fmt.Sprintf(`{
		"DuoWorkflow": {
			"Service": {"URI": %q, "Headers": {}, "Secure": false},
			"WorkflowID": %q,
			"LockConcurrentFlow": %t,
			"Detached": true
		}
	}`, grpcServer.Addr, testWorkflowID, lockConcurrentFlow))
	t.Cleanup(apiServer.Close)

	rdb := initRdb(t)
	backend := http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {})
	handler := NewHandler(apiClient, rdb, backend, "")
	if configure != nil {
		configure(handler)
	}

	t.Cleanup(func() {
		require.Eventually(t, func() bool { return activeRunners(handler) == 0 }, 5*time.Second, 10*time.Millisecond,
			"detached runs must end before the test does")
		require.Eventually(t, func() bool { return detachedRunSlotsHeld(handler) == 0 }, 5*time.Second, 10*time.Millisecond,
			"every detached run must release its slot")
	})

	httpServer := httptest.NewServer(handler.BuildHTTP())
	t.Cleanup(httpServer.Close)

	return detachedSetup{server: httpServer, handler: handler, rdb: rdb}
}

func activeRunners(h *Handler) int {
	n := 0
	h.runners.Range(func(_, _ any) bool {
		n++
		return true
	})

	return n
}

func detachedRunSlotsHeld(h *Handler) int {
	h.runnersMu.Lock()
	defer h.runnersMu.Unlock()

	return h.detachedRuns
}

func lockHeld(t *testing.T, rdb *redis.Client) bool {
	t.Helper()

	n, err := rdb.Exists(context.Background(), workflowLockPrefix+testWorkflowID).Result()
	require.NoError(t, err)

	return n > 0
}

func TestBuildHTTP_Detached_KeepsRunningAfterTheResponse(t *testing.T) {
	responses := make(chan *pb.ActionResponse, 1)
	sendAfterResponse := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		<-sendAfterResponse

		action := &pb.Action{
			RequestID: "req-run-command",
			Action:    &pb.Action_RunCommand{RunCommand: &pb.RunCommandAction{Program: "ls"}},
		}
		if err := stream.Send(action); err != nil {
			return err
		}

		event, err := stream.Recv()
		if err != nil {
			return err
		}
		responses <- event.GetActionResponse()

		return nil
	}

	s := setupDetachedHandler(t, grpcServer, true, nil)

	resp := postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`)
	require.Equal(t, http.StatusAccepted, resp.statusCode)
	require.Empty(t, resp.body, "a detached run streams nothing to the caller")
	require.True(t, lockHeld(t, s.rdb), "the run holds the workflow lock after the response")

	close(sendAfterResponse)

	select {
	case response := <-responses:
		require.Equal(t, "req-run-command", response.RequestID)
		require.Contains(t, response.GetPlainTextResponse().Error, "cannot be executed by this client")
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the run to continue after the response")
	}

	require.Eventually(t, func() bool { return !lockHeld(t, s.rdb) }, 5*time.Second, 10*time.Millisecond,
		"the lock is released once the run ends")
}

func TestBuildHTTP_Detached_AcceptsWhenNoActionArrivesInTime(t *testing.T) {
	release := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		<-release

		return nil
	}

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.detachedAcceptTimeout = 50 * time.Millisecond
	})
	defer close(release)

	resp := postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`)
	require.Equal(t, http.StatusAccepted, resp.statusCode)
	require.True(t, lockHeld(t, s.rdb), "the run is still going after the response")
	require.Equal(t, 1, activeRunners(s.handler))
}

func TestBuildHTTP_Detached_EndsBeforeAcceptance(t *testing.T) {
	tests := []struct {
		name         string
		recvErr      error
		expectStatus int
	}{
		{
			name:         "quota exceeded",
			recvErr:      status.Error(codes.ResourceExhausted, "USAGE_QUOTA_EXCEEDED: out of credits"),
			expectStatus: http.StatusForbidden,
		},
		{
			name:         "request rejected by Duo Workflow Service",
			recvErr:      status.Error(codes.InvalidArgument, "goal is empty"),
			expectStatus: http.StatusBadRequest,
		},
		{
			name:         "internal Duo Workflow Service error",
			recvErr:      status.Error(codes.Internal, "boom"),
			expectStatus: http.StatusInternalServerError,
		},
		{
			name:         "Duo Workflow Service draining",
			recvErr:      status.Error(codes.Unavailable, "DWS_SERVER_SHUTDOWN"),
			expectStatus: http.StatusServiceUnavailable,
		},
		{
			name:         "workflow finished without an action",
			expectStatus: http.StatusAccepted,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			grpcServer := setupTestServer(t)
			grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
				if _, err := recvStartRequest(stream); err != nil {
					return err
				}

				return tt.recvErr
			}

			s := setupDetachedHandler(t, grpcServer, true, nil)

			resp := postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`)
			require.Equal(t, tt.expectStatus, resp.statusCode)
		})
	}
}

func TestBuildHTTP_Detached_RejectsAConcurrentRunOfTheSameWorkflow(t *testing.T) {
	release := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		// The losing request never sends a start request, so this errors for it.
		if event, err := stream.Recv(); err != nil || event.GetStartRequest() == nil {
			return nil
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		<-release

		return nil
	}

	s := setupDetachedHandler(t, grpcServer, true, nil)
	defer close(release)

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)
	require.Equal(t, http.StatusConflict, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)
}

func TestBuildHTTP_Detached_RunsWithoutALockWhenLockingIsDisabled(t *testing.T) {
	release := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		<-release

		return nil
	}

	s := setupDetachedHandler(t, grpcServer, false, nil)
	defer close(release)

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)
	require.False(t, lockHeld(t, s.rdb))
}

func TestBuildHTTP_Detached_FailsWhenTheLockIsUnavailable(t *testing.T) {
	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		// No start request arrives: the run fails on the lock before sending it.
		_, _ = stream.Recv()
		return nil
	}

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.rdb = unreachableRedis(t)
	})

	resp := postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`)
	require.Equal(t, http.StatusServiceUnavailable, resp.statusCode)
}

// stopOnRequest is a Duo Workflow Service that accepts the start request,
// sends a checkpoint, and reports the reason of the stop request it receives,
// acknowledging it the way it acknowledges an infrastructure stop.
func stopOnRequest(stopReasons chan<- string) func(pb.DuoWorkflow_ExecuteWorkflowServer) error {
	return func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		event, err := stream.Recv()
		if err != nil {
			return err
		}
		stopReasons <- event.GetStopWorkflow().GetReason()

		return status.Error(codes.Unavailable, "workflow execution interrupted")
	}
}

func TestBuildHTTP_Detached_StopsTheWorkflowAtTheRunLimit(t *testing.T) {
	stopReasons := make(chan string, 1)

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = stopOnRequest(stopReasons)

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.detachedRunLimit = 100 * time.Millisecond
	})

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	select {
	case reason := <-stopReasons:
		require.Equal(t, reasonRunLimit, reason)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the run limit to stop the workflow")
	}

	require.Eventually(t, func() bool { return !lockHeld(t, s.rdb) }, 5*time.Second, 10*time.Millisecond,
		"the lock is released once the run is stopped")
}

func TestBuildHTTP_Detached_StoppedByShutdown(t *testing.T) {
	stopReasons := make(chan string, 1)

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = stopOnRequest(stopReasons)

	s := setupDetachedHandler(t, grpcServer, true, nil)

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	// An expired grace period stops the run at once.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	require.NoError(t, s.handler.Shutdown(ctx))

	select {
	case reason := <-stopReasons:
		require.Equal(t, reasonServerShutdown, reason)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the shutdown to stop the workflow")
	}

	require.Eventually(t, func() bool { return !lockHeld(t, s.rdb) }, 5*time.Second, 10*time.Millisecond,
		"the lock is released so the run can be dispatched elsewhere")
}

func TestBuildHTTP_Detached_RefusedOnceDraining(t *testing.T) {
	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(_ pb.DuoWorkflow_ExecuteWorkflowServer) error {
		t.Error("a run refused by the drain must not reach Duo Workflow Service")
		return nil
	}

	s := setupDetachedHandler(t, grpcServer, true, nil)

	require.NoError(t, s.handler.Shutdown(context.Background()))

	resp := postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`)
	require.Equal(t, http.StatusServiceUnavailable, resp.statusCode)
	require.False(t, lockHeld(t, s.rdb), "a refused run must not hold the workflow lock")
	require.Zero(t, activeRunners(s.handler))
}

// A run that passes the early check while a drain starts is still refused
// when it registers.
func TestHandler_RegisterRefusesDetachedRunsOnceDraining(t *testing.T) {
	h := NewHandler(nil, nil, nil, "")
	require.NoError(t, h.Shutdown(context.Background()))

	require.False(t, h.register(&runner{}, transportDetached))
	require.True(t, h.register(&runner{}, transportWebSocket), "only detached runs are refused")
	require.Equal(t, 1, activeRunners(h))
}

func TestBuildHTTP_Detached_RefusedOnceTheProcessIsFull(t *testing.T) {
	var starts atomic.Int32
	release := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}
		starts.Add(1)

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		<-release

		return nil
	}

	// Without the lock, so that the second run is refused by the cap and not by
	// the lock on the shared test workflow.
	s := setupDetachedHandler(t, grpcServer, false, func(h *Handler) {
		h.maxDetachedRuns = 1
	})

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	rejectedBefore := testutil.ToFloat64(detachedRunsRejectedTotal)
	require.Equal(t, http.StatusServiceUnavailable, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)
	require.InDelta(t, rejectedBefore+1, testutil.ToFloat64(detachedRunsRejectedTotal), 0)
	require.Equal(t, int32(1), starts.Load(), "a refused run must not reach Duo Workflow Service")

	close(release)
	require.Eventually(t, func() bool { return detachedRunSlotsHeld(s.handler) == 0 }, 5*time.Second, 10*time.Millisecond,
		"the slot is released once the run ends")

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)
}

func TestBuildHTTP_Detached_ReleasesTheSlotWhenTheRunnerCannotStart(t *testing.T) {
	testhelper.ConfigureSecret()

	// Set up by hand rather than with setupDetachedHandler: the run never gets
	// as far as Redis or Duo Workflow Service. The URI is unparseable, so the
	// runner fails to initialize.
	apiServer, apiClient := setupAPIServer(t, fmt.Sprintf(`{
		"DuoWorkflow": {
			"Service": {"URI": "dns://%%zz", "Headers": {}, "Secure": false},
			"WorkflowID": %q,
			"Detached": true
		}
	}`, testWorkflowID))
	t.Cleanup(apiServer.Close)

	handler := NewHandler(apiClient, nil, http.NotFoundHandler(), "")
	server := httptest.NewServer(handler.BuildHTTP())
	t.Cleanup(server.Close)

	require.Equal(t, http.StatusBadGateway, postStartRequest(t, server, `{"goal": "fix the pipeline"}`).statusCode)
	require.Zero(t, detachedRunSlotsHeld(handler))
}

// ignoreStop is a Duo Workflow Service that never acknowledges a stop request:
// it reads until workhorse closes the stream.
func ignoreStop(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
	for {
		if _, err := stream.Recv(); err != nil {
			return nil
		}
	}
}

func TestBuildHTTP_Detached_EndsWhenADrainStopIsNotAcknowledged(t *testing.T) {
	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}

		if err := stream.Send(checkpointAction("req-1")); err != nil {
			return err
		}

		return ignoreStop(stream)
	}

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.stopWorkflowTimeout = 50 * time.Millisecond
	})

	require.Equal(t, http.StatusAccepted, postStartRequest(t, s.server, `{"goal": "fix the pipeline"}`).statusCode)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	require.NoError(t, s.handler.Shutdown(ctx))

	require.Eventually(t, func() bool { return activeRunners(s.handler) == 0 }, 5*time.Second, 10*time.Millisecond,
		"the run must not outlive its released lock")
}

func TestBuildHTTP_Detached_DrainedBeforeAcceptance(t *testing.T) {
	startReceived := make(chan struct{})

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := recvStartRequest(stream); err != nil {
			return err
		}
		close(startReceived)

		return ignoreStop(stream)
	}

	s := setupDetachedHandler(t, grpcServer, true, func(h *Handler) {
		h.stopWorkflowTimeout = 50 * time.Millisecond
		h.detachedAcceptTimeout = 5 * time.Second
	})

	statusCodes := make(chan int, 1)
	go func() {
		resp, err := s.server.Client().Post(s.server.URL+"/execute", "application/json", strings.NewReader(`{"goal": "fix the pipeline"}`))
		if err != nil {
			statusCodes <- 0
			return
		}
		_ = resp.Body.Close()
		statusCodes <- resp.StatusCode
	}()

	select {
	case <-startReceived:
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the start request")
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	require.NoError(t, s.handler.Shutdown(ctx))

	select {
	case statusCode := <-statusCodes:
		require.Equal(t, http.StatusServiceUnavailable, statusCode)
	case <-time.After(5 * time.Second):
		t.Fatal("timed out waiting for the response")
	}
}
