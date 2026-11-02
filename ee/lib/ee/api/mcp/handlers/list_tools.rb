# frozen_string_literal: true

module EE
  module API
    module Mcp
      module Handlers
        module ListTools
          extend ActiveSupport::Concern
          extend ::Gitlab::Utils::Override

          ASK_META = { 'anthropic/requiresUserInteraction' => true }.freeze

          prepended do
            include ::Gitlab::Utils::StrongMemoize
          end

          private

          override :governed_tool_data
          def governed_tool_data(tool_data, tool_name, current_user)
            return super unless ::Ai::ToolRules::McpGovernance.enabled_anywhere?

            governance = mcp_governance(current_user)
            return if governance.permission_for(tool_name.to_s) == ::Ai::ToolRules::Permissions::DENY
            return super unless governance.explicit_permission_for(tool_name.to_s) == ::Ai::ToolRules::Permissions::ASK

            super.deep_merge(_meta: ASK_META)
          end

          def mcp_governance(current_user)
            strong_memoize_with(:mcp_governance, current_user) do
              ::Ai::ToolRules::McpGovernance.new(current_user&.governing_namespace, include_projects: false)
            end
          end
        end
      end
    end
  end
end
