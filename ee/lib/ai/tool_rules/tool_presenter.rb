# frozen_string_literal: true

module Ai
  module ToolRules
    module ToolPresenter
      ACRONYMS = %w[CI ASCP GitLab GLQL SAST FP MCP GraphQL MR].freeze

      DISPLAY_NAME_OVERRIDES = {
        'gitlab__user_search' => 'GitLab User Search',
        'post_sast_fp_analysis_to_gitlab' => 'Post SAST False Positive Analysis to GitLab',
        'post_secret_fp_analysis_to_gitlab' => 'Post Secret False Positive Analysis to GitLab'
      }.freeze

      # Each access type resolves on its own, so a project rule that is stricter on one
      # surface does not hide the namespace value of another.
      def self.tool_rule_for(tool_name, namespace_rule:, project_rule:, project_scoped:, mcp_tools: nil)
        scope_rule = project_scoped ? project_rule : namespace_rule
        default_access = default_access_for(tool_name, mcp_tools: mcp_tools)

        {
          id: tool_name,
          name: display_name_for(tool_name),
          action_type: Registry.action_type_of(tool_name, mcp_tools: mcp_tools),
          category: Registry.category_for(tool_name, mcp_tools: mcp_tools),
          source: Registry.source_for(tool_name, mcp_tools: mcp_tools),
          configured_access: Permissions::ACCESS_TYPES.index_with { |type| scope_rule && scope_rule[type] },
          default_access: default_access
        }.merge(
          Permissions::ACCESS_TYPES.index_with do |access_type|
            most_restrictive([namespace_rule, project_rule], access_type) || default_access[access_type]
          end
        )
      end

      def self.default_access_for(tool_name, mcp_tools: nil)
        default = Registry.default_permission_of(tool_name, mcp_tools: mcp_tools)

        {
          web_access: default,
          local_access: default,
          background_access: Permissions.background_effective(default)
        }
      end

      def self.most_restrictive(rules, access_type)
        rules.filter_map { |rule| rule[access_type] if rule }
          .max_by { |permission| Permissions::RESTRICTIVENESS[permission] }
      end
      private_class_method :most_restrictive

      def self.display_name_for(tool_name)
        DISPLAY_NAME_OVERRIDES.fetch(tool_name) do
          tool_name.split('_').map do |word|
            ACRONYMS.find { |a| a.downcase == word } || word.capitalize
          end.join(' ')
        end
      end
    end
  end
end
