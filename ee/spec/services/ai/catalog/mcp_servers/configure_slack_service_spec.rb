# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServers::ConfigureSlackService, :enable_admin_mode, feature_category: :integrations do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:admin) { create(:admin) }

  subject(:result) do
    described_class.new(
      organization: organization,
      current_user: admin,
      client_id: 'gitlab-slack-app-id',
      client_secret: 'gitlab-slack-app-secret'
    ).execute
  end

  before do
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(admin).and_return(true)
  end

  describe '#execute' do
    it 'creates the Slack MCP server for the GitLab for Slack app', :aggregate_failures do
      expect { result }.to change { Ai::Catalog::McpServer.count }.by(1)

      expect(result).to be_success
      expect(result.payload[:mcp_server]).to have_attributes(
        organization: organization,
        created_by: admin,
        name: 'Slack',
        description: described_class::DESCRIPTION,
        url: 'https://mcp.slack.com/mcp',
        homepage_url: 'https://docs.slack.dev/ai/slack-mcp-server',
        transport: 'http',
        auth_type: 'oauth',
        oauth_client_id: 'gitlab-slack-app-id',
        oauth_client_secret: 'gitlab-slack-app-secret'
      )
    end

    context 'when a Slack MCP server already exists' do
      let_it_be(:mcp_server) do
        create(:ai_catalog_mcp_server, :with_oauth,
          organization: organization, url: 'https://mcp.slack.com/mcp',
          description: 'Custom description', homepage_url: 'https://example.com/slack',
          oauth_client_id: 'old-slack-app-id', oauth_client_secret: 'old-secret')
      end

      it 'updates only its OAuth credentials instead of creating another', :aggregate_failures do
        expect { result }.not_to change { Ai::Catalog::McpServer.count }

        expect(result).to be_success
        expect(mcp_server.reload).to have_attributes(
          description: 'Custom description',
          homepage_url: 'https://example.com/slack',
          oauth_client_id: 'gitlab-slack-app-id',
          oauth_client_secret: 'gitlab-slack-app-secret'
        )
      end
    end
  end
end
