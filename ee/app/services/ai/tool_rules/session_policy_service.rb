# frozen_string_literal: true

module Ai
  module ToolRules
    # Resolves the admin tool rules that govern a Duo Workflow session. Shared by the session
    # token claim and the session approval check, so both resolve rules the same way.
    class SessionPolicyService
      EMPTY_TOOL_POLICIES = {
        pre_approved_tools: [].freeze, denied_tools: [].freeze, ask_tools: [].freeze
      }.freeze

      def initialize(container:, environment:, workflow_definition:)
        @container = container
        @environment = environment
        @workflow_definition = workflow_definition
      end

      # @return [Hash] the ResolutionService payload, or EMPTY_TOOL_POLICIES when there is no
      #   container, the session is ungoverned, or resolution fails
      def execute
        return EMPTY_TOOL_POLICIES unless @container

        surface = GovernanceSurface.for(
          environment: @environment, container: @container, workflow_definition: @workflow_definition
        )
        return EMPTY_TOOL_POLICIES if GovernanceSurface.ungoverned?(surface)

        result = ResolutionService.new(
          namespace: @container.root_ancestor,
          surface: surface || :web,
          project: @container.is_a?(::Project) ? @container : nil
        ).execute

        result.success? ? result.payload : EMPTY_TOOL_POLICIES
      end
    end
  end
end
