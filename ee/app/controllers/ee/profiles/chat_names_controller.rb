# frozen_string_literal: true

module EE
  module Profiles
    module ChatNamesController
      extend ::Gitlab::Utils::Override

      private

      override :after_create_path
      def after_create_path(chat_name)
        mcp_server = slack_mcp_server_to_connect(chat_name)
        return super unless mcp_server

        oauth_mcp_connectors_connect_path(id: mcp_server.id, return_to: super)
      end

      def slack_mcp_server_to_connect(chat_name)
        return unless chat_name.persisted? && slack_app_params?
        return unless ::Feature.enabled?(:slack_duo_agent, current_user)
        return unless ::Ai::Catalog.user_can_access_experimental_and_beta_features?(current_user)
        return unless ::Feature.enabled?(:slack_duo_mcp_server, current_user)
        return unless can?(current_user, :read_ai_catalog_mcp_server, ::Current.organization)

        ::Ai::Catalog::McpServers::SlackHelper.gitlab_slack_app_server(::Current.organization)
      end
    end
  end
end
