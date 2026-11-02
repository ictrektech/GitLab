# frozen_string_literal: true

module Ai
  module ToolRules
    class ResolutionService
      include ::Gitlab::Utils::StrongMemoize

      PRIVILEGE_GROUP_TO_CONSTANT = {
        read_only_gitlab: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
        read_only_files: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES,
        read_write_gitlab: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
        read_write_files: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES,
        run_commands: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS,
        use_git: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT,
        run_mcp_tools: ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_MCP_TOOLS
      }.freeze

      def initialize(namespace:, surface: :web, project: nil, rules: nil)
        @namespace = namespace
        @surface = surface
        @project = project
        @rules = rules
      end

      # @return [ServiceResponse] the allow, ask and deny lists for the surface, or an error
      #   when the surface is ungoverned
      def execute
        if ungoverned_surface?
          track_ungoverned_surface!
          return ungoverned_surface_error
        end

        rules = effective_rules

        agent_privileges = []
        pre_approved_agent_privileges = []
        pre_approved_tools = []
        denied_tools = []
        ask_tools = []

        # Walk every mapped group, not just those with a privilege constant, so a rule on a
        # constant-less group like agent_internal is enforced instead of silently skipped.
        ::Ai::ToolRules::Registry::PRIVILEGE_GROUP_MAPPING.each_key do |group|
          constant = PRIVILEGE_GROUP_TO_CONSTANT[group]
          fallback = fallback_permission(group)
          denied_tools.concat(explicitly_configured_tools_for_group(group, rules, Permissions::DENY))
          pre_approved_tools.concat(explicitly_configured_tools_for_group(group, rules, Permissions::ALLOW))
          ask_tools.concat(explicitly_configured_tools_for_group(group, rules, Permissions::ASK))

          # MCP names are absent from the catalog mapping resolve_group reads, so an MCP
          # rule can neither swing a group verdict nor count towards its quorum.
          case resolve_group(group, rules, fallback)
          when :deny
            next
          when :ask
            agent_privileges << constant if constant
            # The group loses its blanket pre-approval, but tools that still resolve to
            # allow keep theirs. Otherwise one ask rule silently demotes every tool the
            # admin left at a default of allow, which the settings page still shows as allow.
            pre_approved_tools.concat(allowed_tools_for_group(group, rules, fallback))
          when :allow
            if constant
              agent_privileges << constant
              pre_approved_agent_privileges << constant
            end

            pre_approved_tools.concat(allowed_tools_for_group(group, rules, fallback))
          end
        end

        # Belong to no privilege group, so the loop above never reaches them, and they take
        # no group fallback: an unruled MCP tool keeps whatever its annotations gave it.
        denied_tools.concat(explicitly_configured_mcp_tools(mcp_tools, rules, Permissions::DENY))
        pre_approved_tools.concat(explicitly_configured_mcp_tools(mcp_tools, rules, Permissions::ALLOW))
        ask_tools.concat(explicitly_configured_mcp_tools(mcp_tools, rules, Permissions::ASK))

        agent_privileges << ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
        pre_approved_agent_privileges << ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS

        # Two catalog rules can share one MCP spelling, so the most restrictive verdict
        # must win per emitted name as well, not only per rule.
        denied = emit(denied_tools, mcp_tools)
        asked = emit(ask_tools, mcp_tools) - denied
        allowed = emit(pre_approved_tools, mcp_tools, twins: false) - denied - asked

        ServiceResponse.success(payload: {
          agent_privileges: agent_privileges,
          pre_approved_agent_privileges: pre_approved_agent_privileges,
          pre_approved_tools: allowed,
          denied_tools: denied,
          ask_tools: asked
        })
      end

      # Where a project rule exists, most restrictive wins, projects can only escalate,
      # never loosen a namespace-level policy.
      # Guarded separately from #execute so a direct caller cannot skip the surface check.
      def effective_rules
        if ungoverned_surface?
          track_ungoverned_surface!
          return {}
        end

        merge_rules(namespace_rules, project_rules)
      end
      strong_memoize_attr :effective_rules

      def permission_for(tool_name)
        explicit_permission_for(tool_name) || default_permission_for(tool_name)
      end

      def explicit_permission_for(tool_name)
        governing_names(tool_name)
          .filter_map { |name| rule_permission(name) }
          .max_by { |permission| Permissions::RESTRICTIVENESS.fetch(permission.to_s, -1) }
      end

      private

      def mcp_tools
        ::Ai::ToolRules::GovernedMcpTools.for(@namespace)
      end
      strong_memoize_attr :mcp_tools

      def namespace_rules
        return ::Ai::ToolRule.for_namespace(@namespace.id).index_by(&:tool_name) unless @rules

        @rules.select { |rule| rule.project_id.nil? }.index_by(&:tool_name)
      end

      def project_rules
        return {} unless @project
        return ::Ai::ToolRule.for_project(@project.id).index_by(&:tool_name) unless @rules

        @rules.select { |rule| rule.project_id == @project.id }.index_by(&:tool_name)
      end

      def governing_names(tool_name)
        [tool_name, *mcp_tools.identities_for(tool_name)].uniq
      end

      def default_permission_for(tool_name)
        default_names(tool_name)
          .map { |name| ::Ai::ToolRules::Registry.default_permission_of(name, mcp_tools: mcp_tools) }
          .max_by { |permission| Permissions::RESTRICTIVENESS.fetch(permission.to_s, -1) }
      end

      def default_names(tool_name)
        mcp_tools.identities_for(tool_name).presence || [tool_name]
      end

      def rule_permission(tool_name)
        effective_rules[tool_name]&.access_for(@surface)
      end

      # Merges namespace and project rules, applying most-restrictive-wins per tool.
      # Note: Hash#merge with a block only fires for keys present in both hashes.
      # Keys only in project_rules (no matching namespace rule) are added as-is from the project.
      def merge_rules(namespace_rules, project_rules)
        return namespace_rules if project_rules.empty?

        namespace_rules.merge(project_rules) do |_tool_name, ns_rule, proj_rule|
          most_restrictive_rule(ns_rule, proj_rule)
        end
      end

      # Returns the more restrictive of two rules for the current surface.
      # Projects cannot loosen a namespace-level policy.
      def most_restrictive_rule(ns_rule, proj_rule)
        ns_permission = ns_rule.access_for(@surface)
        proj_permission = proj_rule.access_for(@surface)

        # If namespace has no value for this surface, project rule can set it freely.
        return proj_rule if ns_permission.nil?

        # If project has no value for this surface, keep the namespace rule.
        return ns_rule if proj_permission.nil?

        ns_score = Permissions::RESTRICTIVENESS[ns_permission.to_s]
        proj_score = Permissions::RESTRICTIVENESS[proj_permission.to_s]

        proj_score > ns_score ? proj_rule : ns_rule
      end

      def resolve_group(group, rules, fallback)
        governed = ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: group)

        permissions = governed.filter_map do |tool_name|
          rules[tool_name]&.access_for(@surface)
        end

        # Tools without an explicit value for this surface keep the group default, so
        # a partial `allow` cannot pre-approve tools an admin never configured, and a
        # partial `deny` cannot make the whole group unavailable either.
        permissions << fallback.to_s if permissions.size < governed.size

        return fallback if permissions.empty?
        return :deny if permissions.all?(Permissions::DENY)
        return :allow if permissions.all?(Permissions::ALLOW)

        :ask
      end

      def ungoverned_surface?
        ::Ai::ToolRules::GovernanceSurface.ungoverned?(@surface)
      end

      # Loud in dev and test, tracked in production. Callers should never get here.
      def track_ungoverned_surface!
        ::Gitlab::ErrorTracking.track_and_raise_for_dev_exception(
          ArgumentError.new(
            'ResolutionService received an ungoverned surface; check GovernanceSurface.ungoverned? first'
          ),
          namespace_id: @namespace&.id
        )
      end

      def ungoverned_surface_error
        ServiceResponse.error(message: 'Surface is ungoverned', reason: :ungoverned_surface)
      end

      def fallback_permission(group)
        permission = ::Ai::ToolRules::Registry.default_permission_for(group_name: group)

        # On the background surface an unset permission resolves to `allow` (via
        # background_effective) so existing pipelines keep working and admins opt in
        # with explicit rules. Reached only when the background-governance flag is on.
        permission = ::Ai::ToolRules::Permissions.background_effective(permission) if background_surface?

        permission.to_sym
      end

      def background_surface?
        @surface.to_s == ::Ai::ToolRules::GovernanceSurface::BACKGROUND.to_s
      end

      def allowed_tools_for_group(group, rules, fallback)
        ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: group).select do |tool_name|
          rule = rules[tool_name]
          permission = rule ? rule.access_for(@surface) : fallback.to_s

          # No value for this surface falls back to the group default, so enforcement
          # matches the displayed default and another surface's rule can't demote it here.
          permission = fallback.to_s if permission.nil?

          permission == Permissions::ALLOW
        end
      end

      # @param twins [Boolean] see {Ai::ToolRules::Registry.to_mcp_tool_names}
      def emit(tool_names, mcp_tools, twins: true)
        ::Ai::ToolRules::Registry.to_mcp_tool_names(tool_names.uniq, mcp_tools: mcp_tools, twins: twins)
      end

      def explicitly_configured_mcp_tools(mcp_tools, rules, permission)
        mcp_tools.rulable_names.select do |tool_name|
          rules[tool_name]&.access_for(@surface) == permission
        end
      end

      def explicitly_configured_tools_for_group(group, rules, permission)
        ::Ai::ToolRules::Registry.governed_tool_names_for(group_name: group).select do |tool_name|
          rule = rules[tool_name]
          next false unless rule

          rule.access_for(@surface) == permission
        end
      end
    end
  end
end
