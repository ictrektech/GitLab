# frozen_string_literal: true

module Ai
  module Catalog
    module McpServers
      class SlackConfigService
        include Gitlab::Utils::StrongMemoize
        include AuthHeaders

        SERVER_KEY = :slack

        def initialize(current_user, namespace:)
          @current_user = current_user
          @namespace = namespace
        end

        def execute
          return {} unless namespace && allowed?
          return {} unless mcp_server && mcp_servers_user
          return {} if blocked?

          { SERVER_KEY => { URL: mcp_server.url, Headers: build_mcp_server_headers(mcp_server, mcp_servers_user) } }
        end

        private

        attr_reader :current_user, :namespace

        def allowed?
          Ability.allowed?(current_user, :read_ai_catalog_mcp_server, namespace.organization)
        end

        def mcp_server
          ::Ai::Catalog::McpServers::SlackHelper.gitlab_slack_app_server(namespace.organization)
        end
        strong_memoize_attr :mcp_server

        def mcp_servers_user
          mcp_server.mcp_servers_users.find_by_user_id(current_user.id)
        end
        strong_memoize_attr :mcp_servers_user

        def blocked?
          return false unless Feature.enabled?(:mcp_server_block_enforcement, namespace.root_ancestor)

          ::Ai::Catalog::McpServerBlock.blocked_server_ids_for(namespace, [mcp_server.id]).exists?
        end
      end
    end
  end
end
