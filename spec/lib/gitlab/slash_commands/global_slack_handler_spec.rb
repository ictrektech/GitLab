# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SlashCommands::GlobalSlackHandler, feature_category: :integrations do
  include AfterNextHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let_it_be_with_reload(:slack_integration) do
    create(:gitlab_slack_application_integration, project: project).slack_integration
  end

  let(:chat_name) { instance_double(ChatName, user: user) }
  let(:verification_token) { '123' }

  before do
    stub_application_setting(slack_app_verification_token: verification_token)
  end

  def handler(params)
    described_class.new(params)
  end

  def handler_with_valid_token(params)
    handler(params.merge(token: verification_token))
  end

  it 'does not serve a request if token is invalid' do
    result = handler(token: '123456', text: 'help').trigger

    expect(result).to be_falsey
  end

  it 'does not count a request with an invalid token against the workspace' do
    expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

    handler(token: '123456', text: 'help', team_id: slack_integration.team_id).trigger
  end

  context 'when the workspace is over the rate limit', :clean_gitlab_redis_rate_limiting do
    let(:params) { { text: 'help', team_id: slack_integration.team_id } }

    let(:log_entry) do
      {
        message: 'Application_Rate_Limiter_Request',
        env: :slack_app_commands_request_limit,
        slack_workspace: slack_integration.team_id
      }
    end

    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:slack_app_commands, scope: { slack_workspace: slack_integration.team_id })
        .and_return(true)
      allow(Gitlab::AuthLogger).to receive(:error)
    end

    it 'logs the throttle and returns an ephemeral error instead of running the command' do
      expect(Gitlab::SlashCommands::ApplicationHelp).not_to receive(:new)

      result = handler_with_valid_token(params).trigger

      expect(result[:response_type]).to eq(:ephemeral)
      expect(result[:text]).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
      expect(Gitlab::AuthLogger).to have_received(:error).with(log_entry).once
    end

    context 'when the slack_app_workspace_rate_limit feature flag is disabled' do
      before do
        stub_feature_flags(slack_app_workspace_rate_limit: false)
      end

      it 'logs the would-be throttle but still runs the command' do
        expect_next(Gitlab::SlashCommands::ApplicationHelp).to receive(:execute)

        handler_with_valid_token(params).trigger

        expect(Gitlab::AuthLogger).to have_received(:error).with(log_entry).once
      end
    end

    context 'when team_id is missing' do
      let(:params) { { text: 'help' } }

      it 'skips the rate limit check' do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)
        expect_next(Gitlab::SlashCommands::ApplicationHelp).to receive(:execute)

        handler_with_valid_token(params).trigger
      end
    end
  end

  context 'with valid token' do
    context 'with incident declare command' do
      it 'calls command handler with no project alias' do
        expect_next(Gitlab::SlashCommands::Command).to receive(:execute)
        expect_next(ChatNames::FindUserService).to receive(:execute).and_return(chat_name)

        handler_with_valid_token(
          text: "incident declare",
          team_id: slack_integration.team_id
        ).trigger
      end
    end

    it 'calls command handler if project alias is valid' do
      expect_next(Gitlab::SlashCommands::Command).to receive(:execute)
      expect_next(ChatNames::FindUserService).to receive(:execute).and_return(chat_name)

      slack_integration.update!(alias: project.full_path)

      handler_with_valid_token(
        text: "#{project.full_path} issue new title",
        team_id: slack_integration.team_id
      ).trigger
    end

    it 'returns error if project alias not found' do
      expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
      expect_next(
        Gitlab::SlashCommands::Presenters::Error,
        'GitLab error: project or alias not found'
      ).to receive(:message)

      handler_with_valid_token(
        text: "fake/fake issue new title",
        team_id: slack_integration.team_id
      ).trigger
    end

    it 'returns authorization request' do
      expect_next(ChatNames::AuthorizeUserService).to receive(:execute)
      expect_next(Gitlab::SlashCommands::Presenters::Access).to receive(:authorize)

      slack_integration.update!(alias: project.full_path)

      handler_with_valid_token(
        text: "#{project.full_path} issue new title",
        team_id: slack_integration.team_id
      ).trigger
    end

    it 'calls help presenter' do
      expect_next(Gitlab::SlashCommands::ApplicationHelp).to receive(:execute)

      handler_with_valid_token(
        text: "help"
      ).trigger
    end

    context 'when the user cannot use slash commands' do
      before do
        slack_integration.update!(alias: project.full_path)

        allow_next(ChatNames::FindUserService).to receive(:execute).and_return(chat_name)
      end

      context 'when the user is deactivated' do
        let_it_be(:user) { create(:user, :deactivated) }

        it 'asks the user to reactivate their account' do
          expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
          expect_next(Gitlab::SlashCommands::Presenters::Access).to receive(:deactivated)

          handler_with_valid_token(
            text: "#{project.full_path} issue new title",
            team_id: slack_integration.team_id
          ).trigger
        end
      end

      context 'when the user is blocked' do
        let_it_be(:user) { create(:user, :blocked) }

        it 'returns access denied' do
          expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
          expect_next(Gitlab::SlashCommands::Presenters::Access).to receive(:access_denied).with(project)

          handler_with_valid_token(
            text: "#{project.full_path} issue new title",
            team_id: slack_integration.team_id
          ).trigger
        end
      end
    end

    context 'when integration is group-level' do
      let_it_be(:group) { create(:group) }

      let_it_be_with_reload(:slack_integration) do
        create(:gitlab_slack_application_integration, :group, group: group,
          slack_integration: build(:slack_integration, alias: group.full_path)
        ).slack_integration
      end

      it 'returns error that the project alias not found' do
        expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
        expect_next(
          Gitlab::SlashCommands::Presenters::Error,
          'GitLab error: project or alias not found'
        ).to receive(:message)

        handler_with_valid_token(
          text: "#{group.full_path} issue new title",
          team_id: slack_integration.team_id
        ).trigger
      end
    end

    context 'when integration is instance-level' do
      let_it_be_with_reload(:slack_integration) do
        create(:gitlab_slack_application_integration, :instance,
          slack_integration: build(:slack_integration, alias: '_gitlab-instance')
        ).slack_integration
      end

      it 'returns error that the project alias not found' do
        expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
        expect_next(
          Gitlab::SlashCommands::Presenters::Error,
          'GitLab error: project or alias not found'
        ).to receive(:message)

        handler_with_valid_token(
          text: "instance issue new title",
          team_id: slack_integration.team_id
        ).trigger
      end
    end

    context 'when integration is inactive' do
      before do
        slack_integration.integration.deactivate!
      end

      it 'returns error that the project alias not found' do
        expect_next(Gitlab::SlashCommands::Command).not_to receive(:execute)
        expect_next(
          Gitlab::SlashCommands::Presenters::Error,
          'GitLab error: project or alias not found'
        ).to receive(:message)

        handler_with_valid_token(
          text: "#{project.full_path} issue new title",
          team_id: slack_integration.team_id
        ).trigger
      end
    end
  end
end
