# frozen_string_literal: true

module Ai
  module Catalog
    module McpServers
      module SlackHelper
        extend self

        MCP_URL = 'https://mcp.slack.com/mcp'

        def gitlab_slack_app_server(organization)
          slack_app_id = Gitlab::CurrentSettings.slack_app_id
          return if slack_app_id.blank?

          ::Ai::Catalog::McpServer.in_organization(organization).find_by_oauth_client_xid(slack_app_id)
        end

        def gitlab_slack_app_server?(mcp_server)
          slack_app_id = Gitlab::CurrentSettings.slack_app_id

          slack_app_id.present? && mcp_server.oauth_client_id == slack_app_id
        end
      end
    end
  end
end
