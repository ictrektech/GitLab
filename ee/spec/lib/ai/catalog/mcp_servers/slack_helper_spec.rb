# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServers::SlackHelper, feature_category: :duo_agent_platform do
  describe '.gitlab_slack_app_server' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:mcp_server) do
      create(:ai_catalog_mcp_server, :with_oauth, organization: organization, oauth_client_id: 'gitlab-slack-app-id')
    end

    let(:lookup_organization) { organization }

    subject(:server) { described_class.gitlab_slack_app_server(lookup_organization) }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    end

    it 'returns the organization MCP server that uses the GitLab for Slack app' do
      expect(server).to eq(mcp_server)
    end

    context 'when the MCP server belongs to another organization' do
      let(:lookup_organization) { create(:organization) }

      it { is_expected.to be_nil }
    end

    context 'when the MCP server uses another Slack app' do
      before do
        stub_application_setting(slack_app_id: 'other-slack-app-id')
      end

      it { is_expected.to be_nil }
    end

    context 'when the instance has no GitLab for Slack app configured' do
      before do
        stub_application_setting(slack_app_id: nil)
      end

      it { is_expected.to be_nil }
    end
  end

  describe '.gitlab_slack_app_server?' do
    let(:mcp_server) { build(:ai_catalog_mcp_server, oauth_client_id: oauth_client_id) }
    let(:oauth_client_id) { 'gitlab-slack-app-id' }

    subject { described_class.gitlab_slack_app_server?(mcp_server) }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id')
    end

    it { is_expected.to be(true) }

    context 'when the MCP server uses another Slack app' do
      let(:oauth_client_id) { 'other-slack-app-id' }

      it { is_expected.to be(false) }
    end

    context 'when neither the instance nor the MCP server has a client ID' do
      let(:oauth_client_id) { nil }

      before do
        stub_application_setting(slack_app_id: nil)
      end

      it { is_expected.to be(false) }
    end
  end
end
