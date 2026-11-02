package duoworkflow

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"
)

func TestDetachedTransport_ReadClientEvent(t *testing.T) {
	startEvent := &pb.ClientEvent{Response: &pb.ClientEvent_StartRequest{StartRequest: &pb.StartWorkflowRequest{}}}

	t.Run("reports the start request, then the run limit", func(t *testing.T) {
		transport := newDetachedTransport(startEvent, 10*time.Millisecond)
		require.NoError(t, transport.Start())
		defer transport.Close()

		event, err := transport.ReadClientEvent()
		require.NoError(t, err)
		require.Same(t, startEvent, event)

		_, err = transport.ReadClientEvent()
		require.ErrorIs(t, err, errRunLimitReached)

		reason, ok := transport.ReadError(err)
		require.True(t, ok)
		require.Equal(t, reasonRunLimit, reason)
	})

	t.Run("stops waiting once closed, without asking for a stop", func(t *testing.T) {
		transport := newDetachedTransport(startEvent, time.Hour)
		require.NoError(t, transport.Start())

		_, err := transport.ReadClientEvent()
		require.NoError(t, err)

		require.NoError(t, transport.Close())
		require.NoError(t, transport.Close(), "Close is idempotent")

		_, err = transport.ReadClientEvent()
		require.ErrorIs(t, err, errTransportClosed)

		_, ok := transport.ReadError(err)
		require.False(t, ok)
	})
}

func TestDetachedTransport_SendGoingAway(t *testing.T) {
	startEvent := &pb.ClientEvent{Response: &pb.ClientEvent_StartRequest{StartRequest: &pb.StartWorkflowRequest{}}}

	t.Run("ends the run on a workhorse drain", func(t *testing.T) {
		transport := newDetachedTransport(startEvent, time.Hour)
		require.NoError(t, transport.Start())

		_, err := transport.ReadClientEvent()
		require.NoError(t, err)

		require.NoError(t, transport.SendGoingAway(closeReasonWorkhorseShutdown))
		require.True(t, transport.WentAway())

		_, err = transport.ReadClientEvent()
		require.ErrorIs(t, err, errTransportClosed)
	})

	t.Run("only records a drain of Duo Workflow Service, which ends the run itself", func(t *testing.T) {
		transport := newDetachedTransport(startEvent, 10*time.Millisecond)
		require.NoError(t, transport.Start())
		defer transport.Close()

		_, err := transport.ReadClientEvent()
		require.NoError(t, err)

		require.NoError(t, transport.SendGoingAway(closeReasonDWSUnavailable))
		require.True(t, transport.WentAway())

		_, err = transport.ReadClientEvent()
		require.ErrorIs(t, err, errRunLimitReached, "the transport is still open")
	})
}

func TestDetachedTransport_WriteAction(t *testing.T) {
	transport := newDetachedTransport(nil, time.Hour)

	require.NoError(t, transport.WriteAction(context.Background(), checkpointAction("req-1")),
		"checkpoints are dropped, not rejected")

	err := transport.WriteAction(context.Background(), &pb.Action{
		Action: &pb.Action_RunCommand{RunCommand: &pb.RunCommandAction{Program: "ls"}},
	})
	require.ErrorIs(t, err, errActionUnsupported)
}

func TestDetachedTransport_InvalidRequestReason(t *testing.T) {
	transport := newDetachedTransport(nil, time.Hour)
	require.Empty(t, transport.InvalidRequestReason())

	require.NoError(t, transport.SendInvalidRequest("goal is empty"))
	require.Equal(t, "goal is empty", transport.InvalidRequestReason())
}
