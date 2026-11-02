# frozen_string_literal: true

module Ai
  module FlowTriggers
    module FixLoop
      # The gates and the fix runs of a fix loop, for the check of a new fix run and for the end checks.
      # Each gate returns an error response, or nil when it passes.
      class BaseCheck
        include ::Gitlab::Utils::StrongMemoize

        def initialize(merge_request)
          @merge_request = merge_request
        end

        private

        attr_reader :merge_request

        def merge_request_error
          return error_response('Merge request is not open.', :not_open) unless merge_request.opened?
          return error_response('Merge request is a draft.', :draft) if merge_request.draft?

          unless created_by_flow?
            return error_response('No flow session created the merge request.', :not_created_by_flow)
          end

          return unless config.label && merge_request.label_names.exclude?(config.label)

          error_response('Merge request does not have the label of the review configuration.', :label_missing)
        end

        def reviewer_error(reviewer)
          return unless config.other_reviewer?(reviewer)

          error_response('Reviewer is not the reviewer of the review configuration.', :other_reviewer)
        end

        # The last gate. A key with an error has no value, so its gate does not apply. A verdict that a valid
        # configuration would skip does not tell the author about the errors.
        def config_error
          error_response('Review configuration is not valid.', :invalid_config, config:) unless config.valid?
        end

        def config
          Config.for_project(merge_request.target_project)
        end
        strong_memoize_attr :config

        # A merge request that a human created gets no fix run, also when the human is its author.
        def created_by_flow?
          ::Ai::DuoWorkflows::WorkflowMergeRequest.created_for_merge_request(merge_request).exists?
        end

        def fix_runs
          ::Ai::DuoWorkflows::Workflow
            .for_project(merge_request.target_project)
            .for_merge_request(merge_request)
            .with_workflow_definition(FixLoop.developer_reference)
            .trigger_event_merge_request
        end

        # With `before`, the fix runs of the loop at that time.
        def fix_runs_in_loop(before: nil)
          runs = before ? fix_runs.created_before(before) : fix_runs
          start = loop_start(before: before)
          start ? runs.created_after(start) : runs
        end

        # A loop ends when a human marks the merge request as ready, which a stopped loop needs, or when the reviewer
        # approves. A flow that marks it as ready does not end the loop, so a fix run cannot reset its own count.
        # The reviewer is the reviewer of the configuration, because the end of a fix run has no verdict.
        def loop_start(before:)
          notes = merge_request.notes.system
          ready_at = notes.for_note_or_capitalized_note(::SystemNotes::MergeRequestsService::READY_NOTE).inc_author
            .filter_map { |note| note.created_at if note.author.human? && before_limit?(note, before: before) }.max
          approved_at = notes.for_note_or_capitalized_note(::SystemNotes::MergeRequestsService::APPROVED_NOTE)
            .inc_author.filter_map do |note|
              note.created_at if !config.other_reviewer?(note.author) && before_limit?(note, before: before)
            end.max

          [ready_at, approved_at].compact.max
        end

        def before_limit?(note, before:)
          before.nil? || note.created_at < before
        end

        def error_response(message, reason, **payload)
          ServiceResponse.error(message: message, reason: reason, payload: payload)
        end
      end
    end
  end
end
