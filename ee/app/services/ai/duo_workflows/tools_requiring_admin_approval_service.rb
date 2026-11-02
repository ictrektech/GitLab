# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Tools an admin rule sets to Ask or Deny for a session. A saved session approval must
    # never answer for them, or the session owner could approve ahead of the prompt.
    class ToolsRequiringAdminApprovalService
      def initialize(workflow:)
        @workflow = workflow
      end

      # @return [Set<String>]
      def execute
        policies = ::Ai::ToolRules::SessionPolicyService.new(
          container: @workflow.resource_parent,
          environment: @workflow.environment,
          workflow_definition: @workflow.workflow_definition
        ).execute

        (policies[:ask_tools] + policies[:denied_tools]).to_set
      end
    end
  end
end
