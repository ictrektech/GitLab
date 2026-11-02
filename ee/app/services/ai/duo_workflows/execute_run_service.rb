# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Executes the next run of a Duo session: the caller hands over a session
    # and what just happened (input arrived, a tool or plan approval was
    # decided), and the run goes to the runtime the flow's coding environment
    # implies unless the caller overrides it. Intended as the single entry
    # point every surface calls. Callers authorize the acting user; this
    # service enforces no permissions of its own.
    class ExecuteRunService
      RUNTIMES = %i[ci workhorse].freeze
      SUPPORTED_CODING_ENVIRONMENTS = {
        ci: %i[full none],
        workhorse: %i[none]
      }.freeze
      # What the flow is told about this turn's surface. Every runtime forwards
      # these to BuildAdditionalContextService.
      CONTEXT_KEYS = %i[additional_context triggering_conversation event_type client_context].freeze

      def self.runtime_for(workflow_definition, override: nil)
        runtime = override&.to_sym
        return runtime if RUNTIMES.include?(runtime)
        return if runtime

        ::Ai::Catalog::CodingEnvironment.default_runtime_for(workflow_definition)
      end

      # source_branch applies to CI runs only; Workhorse runs have no checkout.
      def initialize(workflow, event:, runtime: nil, context: {}, source_branch: nil)
        context = context.to_h
        unknown_keys = context.keys.map(&:to_sym) - CONTEXT_KEYS
        raise ArgumentError, "Unknown run context keys: #{unknown_keys.join(', ')}" if unknown_keys.any?

        @workflow = workflow
        @event = RunEvent.new(event)
        @runtime = runtime&.to_sym
        @context = context.symbolize_keys.compact
        @source_branch = source_branch
      end

      def execute
        @continuation = !workflow.created?

        return invalid_event unless event.valid_for?(workflow)

        resolved_runtime = resolve_runtime
        return runtime_unknown unless resolved_runtime
        return runtime_mismatch(resolved_runtime) if runtime_mismatch?
        return unsupported_environment(resolved_runtime) unless supported?(resolved_runtime)

        result = resolved_runtime == :ci ? start_ci_run : start_workhorse_run
        return result if result.error?

        ServiceResponse.success(message: result.message, payload: { workflow: workflow, **result.payload })
      end

      private

      attr_reader :workflow, :event, :runtime, :context, :source_branch

      def start_ci_run
        result = ::Ai::DuoWorkflows::Runtimes::Ci.new(
          workflow, params_overrides: resume_params, context: context, source_branch: source_branch
        ).execute

        # Reset only after the run is enqueued, so a failed start never reopens the
        # previous turn's claim. A CI turn waits for a runner and a checkout, so it
        # does not deliver before this reset in practice.
        workflow.reset_messaging_turn! if result.success? && continuation?

        result
      end

      def start_workhorse_run
        approval = event.approval? ? event.workhorse_approval : nil
        # A reply carries the user's text; the first turn passes none, so the
        # worker answers the session's own goal.
        goal = event.input? && workflow.input_required? ? event.text : nil
        # Reset before enqueueing: a fast turn could deliver before a later reset,
        # and nothing between here and perform_async can fail.
        workflow.reset_messaging_turn! if continuation?
        ::Ai::Messaging::ServerSideTurnWorker.perform_async(
          workflow.id, approval, goal, context.as_json
        )

        ServiceResponse.success
      end

      def resolve_runtime
        return runtime if RUNTIMES.include?(runtime)
        return if runtime

        continuation? ? workflow.last_runtime : inferred_runtime
      end

      def runtime_mismatch?
        continuation? && runtime && runtime != workflow.last_runtime
      end

      def inferred_runtime
        ::Ai::Catalog::CodingEnvironment.default_runtime(coding_environment)
      end

      def coding_environment
        @coding_environment ||= ::Ai::Catalog::CodingEnvironment.resolve(
          workflow_definition: workflow.workflow_definition
        )
      end

      def supported?(resolved_runtime)
        SUPPORTED_CODING_ENVIRONMENTS.fetch(resolved_runtime).include?(coding_environment)
      end

      # An approval answers through human_approval/human_message; an input reply
      # carries its text as the fresh goal, overriding the stale
      # DUO_WORKFLOW_GOAL in ResumeWorkflowService. Approval ignores text.
      def resume_params
        return {} unless continuation?
        return { human_approval: event.approved?, human_message: event.message } if event.approval?

        { goal: event.text }
      end

      def continuation?
        @continuation
      end

      def invalid_event
        ServiceResponse.error(message: 'The event is invalid for this workflow', reason: :invalid_event)
      end

      def runtime_unknown
        ServiceResponse.error(message: 'Could not resolve a runtime for this workflow', reason: :runtime_unknown)
      end

      def runtime_mismatch(resolved_runtime)
        ServiceResponse.error(
          message: "The #{resolved_runtime} runtime does not match the workflow's #{workflow.last_runtime} runtime",
          reason: :runtime_mismatch
        )
      end

      def unsupported_environment(resolved_runtime)
        ServiceResponse.error(
          message: "The #{workflow.workflow_definition} flow requires #{coding_environment} coding environment, " \
            "which #{resolved_runtime} does not support",
          reason: :unsupported_environment
        )
      end
    end
  end
end
