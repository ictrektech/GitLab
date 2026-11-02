# frozen_string_literal: true

module Ai
  module Governance
    # Single source of truth for the AI Governance page and its sidebar items,
    # so the controllers and the menus can't drift apart (#629433).
    class PageAvailability
      include Gitlab::Utils::StrongMemoize

      DASHBOARD = 'dashboard'
      TOOL_MANAGEMENT = 'tool-management'
      AGENT_ARTIFACTS = 'agent-artifacts'
      MCP_REGISTRY = 'mcp-registry'
      TABS = [DASHBOARD, TOOL_MANAGEMENT, AGENT_ARTIFACTS, MCP_REGISTRY].freeze

      def initialize(container, user, organization: nil)
        @container = container
        @user = user
        @organization = organization
      end

      # The tool-rules GraphQL surface only resolves top-level groups, so the page
      # exists only on top-level groups and their projects.
      def available?
        return false unless root_group?
        return true if per_tab_permissions?

        container.licensed_ai_features_available? && can?(:read_ai_tool_rule, root_ancestor)
      end
      strong_memoize_attr :available?

      # Tabs whose content the user can see. Each tab checks the subject its data
      # is authorized against. Tab feature flags stay on the frontend.
      def permitted_tabs
        return [] unless available?
        return TABS unless per_tab_permissions?

        TABS.select { |tab| tab_permitted?(tab) }
      end

      private

      attr_reader :container, :user, :organization

      def tab_permitted?(tab)
        case tab
        when DASHBOARD, AGENT_ARTIFACTS then can?(:read_agent_artifacts, container)
        when TOOL_MANAGEMENT then can?(:read_ai_tool_rule, root_ancestor)
        when MCP_REGISTRY then mcp_registry_permitted?
        end
      end

      # Reading the catalog is open to every organization user, so also require the
      # ability the tab's block/allow mutation checks on this container.
      def mcp_registry_permitted?
        organization.present? &&
          can?(:read_ai_catalog_mcp_server, organization) &&
          can?(:block_ai_catalog_mcp_server, container)
      end

      def root_group?
        case container
        when ::Group then container.root?
        when ::Project then root_ancestor.is_a?(::Group)
        else false
        end
      end

      def per_tab_permissions?
        Feature.enabled?(:ai_governance_per_tab_permissions, root_ancestor)
      end

      def root_ancestor
        container.root_ancestor
      end

      def can?(ability, subject)
        Ability.allowed?(user, ability, subject)
      end
    end
  end
end
