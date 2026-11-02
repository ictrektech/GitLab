# frozen_string_literal: true

module WorkItems
  module Decisions
    # Records a clarifying question posted by the workplan flow as an open decision,
    # so answering the question later only has to resolve it.
    class CreateFromDuoQuestionService
      def initialize(note:, workflow:, current_user:)
        @note = note
        @workflow = workflow
        @current_user = current_user
      end

      # @return [ServiceResponse, nil] the create response, or nil when the note isn't a question to record
      def execute
        return unless workplan_workflow?
        return unless payload
        return unless flow_authored?
        return unless work_item&.get_widget(:decision_log)

        CreateService.new(work_item: work_item, current_user: current_user, params: decision_params).execute
      end

      private

      attr_reader :note, :workflow, :current_user

      def workplan_workflow?
        workflow.workflow_definition == ::Ai::Catalog::FoundationalFlow.workplan_v1.reference
      end

      # The workflow ID comes from a client-supplied header, so also require the note to come
      # from the service account running that workflow, not a human posting a payload of their own.
      def flow_authored?
        workflow.service_account_id.present? && note.author_id == workflow.service_account_id
      end

      def payload
        @payload ||= ::Gitlab::WorkItems::DuoQuestion.parse(note.note)
      end

      def work_item
        return unless note.for_issue?

        @work_item ||= ::WorkItem.find_by_id(note.noteable_id)
      end

      def decision_params
        {
          question: title,
          description: s_('WorkItemDecisionLog|GitLab Duo raised this question during review of the work item.'),
          discussion_id: note.discussion_id,
          options: options,
          workflow: workflow
        }
      end

      # The marker form carries no question, so its title comes from the prose around it.
      def title
        question = payload[:question] || ::Gitlab::WorkItems::DuoQuestion.strip_payloads(note.note).squish

        question.truncate(WorkItems::Decision::TITLE_LENGTH_MAX)
      end

      def options
        return [] unless payload[:type] == ::Gitlab::WorkItems::DuoQuestion::QUESTION_TYPE_CLOSED

        payload[:options].first(WorkItems::Decision::MAX_OPTIONS_PER_DECISION).map do |option|
          option.slice(:description, :recommended).merge(content: option[:label])
        end
      end
    end
  end
end
