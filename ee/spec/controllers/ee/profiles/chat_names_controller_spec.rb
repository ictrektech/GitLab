# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Profiles::ChatNamesController, :clean_gitlab_redis_shared_state, feature_category: :integrations do
  let_it_be(:user) { create(:user, organizations: [current_organization]) }
  let_it_be_with_reload(:mcp_server) do
    create(:ai_catalog_mcp_server, :with_oauth,
      organization: current_organization, oauth_client_id: 'gitlab-slack-app-id')
  end

  before do
    sign_in(user)
  end

  describe 'POST #create' do
    let(:chat_name_params) { { team_id: 'T123', chat_id: 'U123', chat_name: 'test_user' } }
    let(:token) { Gitlab::ChatNameToken.new.store!(chat_name_params) }
    let(:integration_accounts_path) { user_settings_integration_accounts_path }

    subject(:create_chat_name) { post :create, params: { token: token } }

    before do
      stub_application_setting(slack_app_id: 'gitlab-slack-app-id', instance_level_ai_beta_features_enabled: true)
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(true)
    end

    it 'continues to connect the Slack MCP server, then returns to the integration accounts' do
      create_chat_name

      expect(response).to redirect_to(
        oauth_mcp_connectors_connect_path(id: mcp_server.id, return_to: integration_accounts_path)
      )
    end

    shared_examples 'redirects to the integration accounts' do
      it 'does not continue to the Slack MCP server' do
        create_chat_name

        expect(response).to redirect_to(integration_accounts_path)
      end
    end

    context 'when the Slack account is already linked to another user' do
      before do
        create(:chat_name, team_id: chat_name_params[:team_id], chat_id: chat_name_params[:chat_id])
      end

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when the account is not a Slack account' do
      let(:chat_name_params) { { team_id: 'mattermost-team', chat_id: 'mattermost-user', chat_name: 'test_user' } }

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when slack_duo_agent is disabled' do
      before do
        stub_feature_flags(slack_duo_agent: false)
      end

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when experiment and beta features are turned off' do
      before do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)
      end

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when slack_duo_mcp_server is disabled' do
      before do
        stub_feature_flags(slack_duo_mcp_server: false)
      end

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when MCP servers are not available to the user' do
      before do
        allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(false)
      end

      it_behaves_like 'redirects to the integration accounts'
    end

    context 'when the organization has no GitLab for Slack app MCP server' do
      before do
        stub_application_setting(slack_app_id: 'other-slack-app-id')
      end

      it_behaves_like 'redirects to the integration accounts'
    end
  end
end
