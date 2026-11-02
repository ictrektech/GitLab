# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServers::SlackConfigService, feature_category: :duo_agent_platform do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, organizations: [organization]) }
  let_it_be(:group) { create(:group, organization: organization) }

  let_it_be_with_reload(:mcp_server) do
    create(:ai_catalog_mcp_server, :with_oauth, organization: organization, oauth_client_id: 'gitlab-slack-app-id')
  end

  let_it_be_with_reload(:mcp_servers_user) do
    create(:ai_catalog_mcp_servers_user, mcp_server: mcp_server, user: user, organization: organization,
      token: 'xoxp-user-token', expires_at: nil)
  end

  let(:namespace) { group }

  subject(:config) { described_class.new(user, namespace: namespace).execute }

  before do
    stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(true)
  end

  describe '#execute' do
    it 'returns the Slack MCP server with the user token' do
      expect(config).to eq(
        slack: { URL: mcp_server.url, Headers: { Authorization: 'Bearer xoxp-user-token' } }
      )
    end

    context 'when the token is about to expire' do
      it 'refreshes it first and sends the refreshed token' do
        mcp_servers_user.update!(expires_at: 1.minute.from_now)

        expect_next_instance_of(Ai::Catalog::McpServers::RefreshTokenService) do |service|
          expect(service).to receive(:execute) do
            mcp_servers_user.update!(token: 'xoxp-refreshed-token')
            ServiceResponse.success
          end
        end

        expect(config.dig(:slack, :Headers, :Authorization)).to eq('Bearer xoxp-refreshed-token')
      end
    end

    context 'when the user has not connected Slack' do
      before do
        mcp_servers_user.destroy!
      end

      it { is_expected.to eq({}) }
    end

    context 'when the Slack MCP server uses another Slack app' do
      before do
        stub_application_setting(slack_app_id: 'other-slack-app-id')
      end

      it { is_expected.to eq({}) }
    end

    context 'when the instance has no GitLab for Slack app configured' do
      before do
        stub_application_setting(slack_app_id: nil)
      end

      it { is_expected.to eq({}) }
    end

    context 'when the GitLab for Slack app MCP server belongs to another organization' do
      before do
        mcp_server.update!(organization: create(:organization))
      end

      it { is_expected.to eq({}) }
    end

    context 'when no MCP server uses the GitLab for Slack app' do
      before do
        mcp_server.update!(oauth_client_id: nil)
      end

      it { is_expected.to eq({}) }
    end

    context 'when there is no namespace' do
      let(:namespace) { nil }

      it { is_expected.to eq({}) }
    end

    context 'when the user is not in the organization' do
      let_it_be(:outsider) { create(:user) }

      subject(:config) { described_class.new(outsider, namespace: namespace).execute }

      before do
        allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(outsider).and_return(true)
        create(:ai_catalog_mcp_servers_user, mcp_server: mcp_server, user: outsider, organization: organization)
      end

      it { is_expected.to eq({}) }
    end

    context 'when MCP servers are not available to the user' do
      before do
        allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(false)
      end

      it { is_expected.to eq({}) }
    end

    context 'when the Slack MCP server is blocked for the namespace' do
      before do
        create(:ai_catalog_mcp_server_block, namespace: group, mcp_server: mcp_server, organization: organization)
      end

      it { is_expected.to eq({}) }

      context 'when mcp_server_block_enforcement is disabled' do
        before do
          stub_feature_flags(mcp_server_block_enforcement: false)
        end

        it { is_expected.to have_key(:slack) }
      end
    end
  end
end
