# frozen_string_literal: true

module Ai
  module Messaging
    # Runs one turn of a server-side flow for a messaging surface and delivers
    # its answer.
    #
    # Unlike most workers this one blocks for the whole turn, unless the turn
    # is detached (below): it holds the HTTP connection to Workhorse, which
    # holds the gRPC stream to the Duo Workflow Service. That is the job. It exists as a worker of its own, rather than
    # inline in the surface's event worker, so the run is not bounded by that
    # worker's own retry semantics and so its fleet concurrency can be capped.
    # Live progress flows through ProgressDeliveryWorker, driven by the
    # checkpoints the flow writes as it runs.
    #
    # With duo_workflow_detached_server_side_execution, the job only starts the
    # turn: Workhorse answers once the run has started and keeps it going on its
    # own, and CallbackWorker delivers the outcome from the workflow's status
    # events. Calling Workhorse from the callers instead is not an option,
    # because some of them are web requests, which must not call back into
    # Rails through Workhorse and wait for the answer.
    #
    # rubocop:disable Scalability/IdempotentWorker -- a turn is not idempotent: re-running resumes the flow from its last checkpoint
    # rubocop:disable Sidekiq/EnforceDatabaseHealthSignalDeferral -- a user is waiting on this turn, and the session's writes come from DWS through the API, which is never deferred
    class ServerSideTurnWorker
      include ApplicationWorker
      include ::Ai::Messaging::ResultDelivery

      feature_category :duo_agent_platform
      data_consistency :sticky
      urgency :low
      worker_has_external_dependencies!

      # Each job pins a Sidekiq thread for a whole turn, so the usual assumption
      # that jobs are short does not hold. Provisional until real traffic informs
      # a better number: sidekiq_concurrency_limit_queue_jobs, labelled by worker,
      # reports how many turns are waiting on this limit.
      concurrency_limit -> { 50 }

      # A turn interrupted by a deploy is re-pushed by Sidekiq and resumes from
      # the flow's last checkpoint, so a duplicate job is wasteful rather than
      # harmful; Workhorse rejects the second one while the first still holds the
      # workflow lock.
      deduplicate :until_executed

      # goal is the message this turn is answering. It is absent for the first
      # turn, whose message is the workflow's own goal, and present for every
      # turn after it: a session's goal stays the message that opened it, the
      # way it does for a chat session driven from a browser.
      #
      # options carries the turn's run context (ExecuteRunService::CONTEXT_KEYS).
      def perform(workflow_id, approval = nil, goal = nil, options = {})
        # A signal left by an earlier stop must not stop this turn. Cleared
        # before the workflow is read, so a stop that lands after the read
        # sets it again, and a stop that lands before is caught below.
        ::Gitlab::DuoWorkflow::WorkhorseStopSignal.clear(workflow_id)

        workflow = find_workflow_on_primary(workflow_id)
        return unless workflow

        # Failed or stopped while queued; that outcome is already delivered, so
        # running now would only resume the session for an answer that gets dropped.
        if workflow.status_terminal?
          log_skip('Session already terminal; not running the turn', workflow_id: workflow.id)
          return
        end

        detached = Feature.enabled?(:duo_workflow_detached_server_side_execution, workflow.user)
        # Before the request: a detached turn can pause before Workhorse even answers.
        mark_detached_turn(workflow) if detached

        result = ::Ai::DuoWorkflows::ServerSideExecutionService.new(
          workflow: workflow, goal: goal.presence || workflow.goal, approval: approval,
          context: options.symbolize_keys.slice(*::Ai::DuoWorkflows::ExecuteRunService::CONTEXT_KEYS),
          detached: detached
        ).execute

        # The turn is still going; CallbackWorker delivers its outcome.
        return if result.success? && result.payload[:detached]

        # A run parked on an approval has produced no answer yet, and the surface
        # cannot answer it until the approval work lands. Delivering the last
        # message here would also claim the delivery and so suppress the real
        # answer once the run resumes and finishes.
        return if result.success? && workflow.awaiting_approval?

        with_adapter(workflow) do |adapter, callback_context|
          next deliver_success(adapter, callback_context, workflow) if result.success?

          deliver_failure(adapter, callback_context, workflow, result.reason || :flow_failed)
        end
      end

      private

      # A sticky replica only has writes from before the enqueue, so it can miss
      # a stop that landed since and whose signal the clear above just removed.
      def find_workflow_on_primary(workflow_id)
        ::Gitlab::Database::LoadBalancing::SessionMap
          .current(::Ai::DuoWorkflows::Workflow.load_balancer)
          .use_primary { ::Ai::DuoWorkflows::Workflow.find_by_id(workflow_id) }
      end

      # If pre-authorization does not grant the detached run, Workhorse streams the
      # turn, both workers try to deliver it and the claim picks one.
      def mark_detached_turn(workflow)
        return if workflow.messaging_callback_context.blank?

        workflow.merge_messaging_callback_context!(::Ai::Messaging::Adapters::Base::DETACHED_TURN_KEY => true)
      end
    end
    # rubocop:enable Scalability/IdempotentWorker
    # rubocop:enable Sidekiq/EnforceDatabaseHealthSignalDeferral
  end
end
