# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::GithubService, feature_category: :importers do
  let_it_be(:user) { create(:user, :with_namespace) }

  let(:token) { 'complex-token' }
  let(:access_params) { { github_access_token: 'ghp_complex-token' } }
  let(:settings) { instance_double(Gitlab::GithubImport::Settings) }
  let(:user_namespace_path) { user.namespace_path }
  let(:optional_stages) { nil }
  let(:timeout_strategy) { "optimistic" }
  let(:pagination_limit) { nil }
  let(:params) do
    {
      repo_id: 123,
      new_name: 'new_repo',
      target_namespace: user_namespace_path,
      optional_stages: optional_stages,
      timeout_strategy: timeout_strategy,
      pagination_limit: pagination_limit
    }
  end

  let(:client) { Gitlab::GithubImport::Client.new(token) }
  let(:project_double) { instance_double(Project, persisted?: true) }

  subject(:github_importer) { described_class.new(client, user, params) }

  before do
    allow(client).to receive_message_chain(:octokit, :rate_limit, :limit)
    allow(client).to receive_message_chain(:octokit, :rate_limit, :remaining).and_return(100)
    allow(Gitlab::GithubImport::Settings).to receive(:new).with(project_double).and_return(settings)

    # catch every call to write, regardless of arguments
    allow(settings).to receive(:write)
  end

  context 'when validating repository size' do
    let(:repository_double) { { name: 'repository', size: 99 } }

    before do
      allow(github_importer).to receive(:authorized?).and_return(true)
      allow(client).to receive_message_chain(:octokit, :repository).and_return({ status: 200 })
      allow(client).to receive_message_chain(:octokit, :collaborators).and_return({ status: 200 })
      allow(client).to receive(:repository).and_return(repository_double)

      allow_next_instance_of(Gitlab::LegacyGithubImport::ProjectCreator) do |creator|
        allow(creator).to receive(:execute).and_return(project_double)
      end
    end

    context 'when there is no repository size limit defined' do
      it 'skips the check, succeeds, and tracks an access level' do
        expect(github_importer.execute(access_params, :github)).to include(status: :success)
        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: nil,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
        expect_snowplow_event(
          category: 'Import::GithubService',
          action: 'create',
          label: 'import_access_level',
          user: user,
          extra: { import_type: 'github', user_role: 'Owner' }
        )
      end
    end

    context 'when the target namespace repository size limit is defined' do
      let_it_be(:group) { create(:group, repository_size_limit: 100) }

      before do
        params[:target_namespace] = group.full_path
      end

      it 'succeeds if the repository is smaller than the limit' do
        expect(github_importer.execute(access_params, :github)).to include(status: :success)
        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: nil,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
        expect_snowplow_event(
          category: 'Import::GithubService',
          action: 'create',
          label: 'import_access_level',
          user: user,
          extra: { import_type: 'github', user_role: 'Not a member' }
        )
      end

      it 'returns error if the repository is larger than the limit' do
        repository_double[:size] = 101

        expect(github_importer.execute(access_params, :github)).to include(
          size_limit_error(repository_double[:name], repository_double[:size], group.repository_size_limit)
        )
      end
    end

    context 'when target namespace repository limit is not defined' do
      let_it_be(:group) { create(:group) }
      let(:repository_size_limit) { 100 }

      before do
        stub_application_setting(repository_size_limit: 100)
      end

      context 'when application size limit is defined' do
        it 'succeeds if the repository is smaller than the limit' do
          expect(github_importer.execute(access_params, :github)).to include(status: :success)
          expect(settings)
            .to have_received(:write)
            .with(
              hash_including(
                optional_stages: nil,
                timeout_strategy: timeout_strategy,
                pagination_limit: pagination_limit
              )
            )
          expect_snowplow_event(
            category: 'Import::GithubService',
            action: 'create',
            label: 'import_access_level',
            user: user,
            extra: { import_type: 'github', user_role: 'Owner' }
          )
        end

        it 'returns error if the repository is larger than the limit' do
          repository_double[:size] = 101

          expect(github_importer.execute(access_params, :github)).to include(
            size_limit_error(repository_double[:name], repository_double[:size], repository_size_limit)
          )
        end
      end
    end

    context 'when optional stages params present' do
      let(:optional_stages) do
        {
          attachments_import: false
        }
      end

      it 'saves optional stages choice to import_data' do
        github_importer.execute(access_params, :github)

        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: optional_stages,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
      end
    end

    context 'when timeout strategy param is present' do
      let(:timeout_strategy) { 'pessimistic' }

      it 'saves timeout strategy to import_data' do
        github_importer.execute(access_params, :github)

        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: optional_stages,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
      end
    end

    context 'when pagination limit param is present' do
      let(:pagination_limit) { 50 }

      it 'saves pagination limit to import_data' do
        github_importer.execute(access_params, :github)

        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: optional_stages,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
      end
    end

    context 'when additional access tokens are present' do
      it 'saves additional access tokens to import_data' do
        github_importer.execute(access_params, :github)

        expect(settings)
          .to have_received(:write)
          .with(
            hash_including(
              optional_stages: optional_stages,
              timeout_strategy: timeout_strategy,
              pagination_limit: pagination_limit
            )
          )
      end
    end
  end

  context 'when validating the continuous import license' do
    let_it_be(:free_group) { create(:group) }

    let(:project_creator) { instance_double(Gitlab::LegacyGithubImport::ProjectCreator, execute: project_double) }
    let(:license_error) do
      {
        status: :error,
        http_status: :unprocessable_entity,
        message: s_("GithubImport|Not available with updates on. Choose a Premium or Ultimate group.")
      }
    end

    before do
      allow(github_importer).to receive(:authorized?).and_return(true)
      allow(client).to receive_message_chain(:octokit, :repository).and_return({ status: 200 })
      allow(client).to receive_message_chain(:octokit, :collaborators).and_return({ status: 200 })
      allow(client).to receive_message_chain(:octokit, :user).and_return({ id: 583231, login: 'octocat' })
      allow(client).to receive(:repository)
        .and_return({ name: 'repository', size: 1, clone_url: 'https://github.com/octocat/repository.git' })
      allow(Gitlab::LegacyGithubImport::ProjectCreator).to receive(:new).and_return(project_creator)
      allow(github_importer).to receive(:track_internal_event)
      allow(project_double).to receive_messages(namespace: nil, import_type: 'github')
      create(:import_user_credential, user: user, provider_account_xid: 583231)
    end

    context 'when continuous sync is checked' do
      let(:optional_stages) { { continuous_sync: 'true' } }

      context 'when namespace plans are checked', :saas do
        let_it_be(:premium_group) { create(:group_with_plan, plan: :premium_plan) }

        before do
          stub_application_setting(check_namespace_plan: true)
          stub_licensed_features(github_continuous_sync: true)
        end

        it 'succeeds when the destination group has a Premium plan' do
          params[:target_namespace] = premium_group.full_path

          expect(github_importer.execute(access_params, :github)).to include(status: :success)
          expect(settings).to have_received(:write).with(hash_including(optional_stages: optional_stages))
        end

        it 'returns an error and does not create the project when the destination group has no plan' do
          params[:target_namespace] = free_group.full_path

          expect(github_importer.execute(access_params, :github)).to eq(license_error)
          expect(project_creator).not_to have_received(:execute)
        end
      end

      context 'when namespace plans are not checked' do
        before do
          params[:target_namespace] = free_group.full_path
        end

        it 'succeeds when the instance is licensed' do
          stub_licensed_features(github_continuous_sync: true)

          expect(github_importer.execute(access_params, :github)).to include(status: :success)
        end

        it 'returns an error and does not create the project when the instance is not licensed' do
          stub_licensed_features(github_continuous_sync: false)

          expect(github_importer.execute(access_params, :github)).to eq(license_error)
          expect(project_creator).not_to have_received(:execute)
        end
      end
    end

    context 'when continuous sync is not checked' do
      let(:optional_stages) { { continuous_sync: 'false', collaborators_import: 'true' } }

      it 'succeeds regardless of the license' do
        stub_licensed_features(github_continuous_sync: false)
        params[:target_namespace] = free_group.full_path

        expect(github_importer.execute(access_params, :github)).to include(status: :success)
        expect(settings).to have_received(:write).with(hash_including(optional_stages: optional_stages))
      end
    end
  end

  context 'when creating the project with continuous sync' do
    let_it_be(:group) { create(:group) }

    let(:optional_stages) { { continuous_sync: 'true' } }
    let(:github_account) { { id: 583231, login: 'octocat' } }
    let(:repository_double) do
      {
        id: 1296269,
        node_id: 'MDEwOlJlcG9zaXRvcnkxMjk2MjY5',
        name: 'hello-world',
        full_name: 'octocat/hello-world',
        default_branch: 'main',
        clone_url: 'https://github.com/octocat/hello-world.git',
        private: false,
        has_wiki: true,
        size: 1
      }
    end

    let!(:user_credential) { create(:import_user_credential, user: user, provider_account_xid: 583231) }

    before_all do
      group.add_owner(user)
    end

    before do
      params[:target_namespace] = group.full_path
      stub_application_setting(import_sources: %w[github gitea])
      stub_licensed_features(github_continuous_sync: true)
      allow(client).to receive_message_chain(:octokit, :repository).and_return({ status: 200 })
      allow(client).to receive_message_chain(:octokit, :user).and_return(github_account)
      allow(client).to receive(:repository).and_return(repository_double)
      allow(Gitlab::GithubImport::Settings).to receive(:new).and_call_original
    end

    shared_examples 'creates the project without continuous sync' do |provider|
      it 'creates the project without a sync repository, setting, or account lookup' do
        result = github_importer.execute(access_params, provider)

        expect(result).to include(status: :success)
        expect(result[:project].import_sync_repository).to be_nil
        expect(Gitlab::GithubImport::Settings.new(result[:project]).enabled?(:continuous_sync)).to be(false)
        expect(client.octokit).not_to have_received(:user)
      end

      it 'does not track that continuous sync was enabled' do
        expect { github_importer.execute(access_params, provider) }
          .not_to trigger_internal_events('enable_import_continuous_sync')
      end
    end

    it 'creates the project together with a provisioning sync repository' do
      result = github_importer.execute(access_params, :github)

      expect(result).to include(status: :success)
      expect(result[:project].import_sync_repository).to be_persisted
      expect(result[:project].import_sync_repository).to have_attributes(
        connected_by_user: user,
        provider: 'github',
        provider_installation_xid: nil,
        provider_account_xid: 583231,
        provider_account_login: 'octocat',
        provider_repository_xid: 1296269,
        provider_repository_node_id: 'MDEwOlJlcG9zaXRvcnkxMjk2MjY5',
        provider_full_name: 'octocat/hello-world',
        provider_default_branch: 'main',
        authority_state: 'provisioning'
      )
    end

    it 'tracks that continuous sync was enabled' do
      allow(Gitlab::InternalEvents).to receive(:track_event).and_call_original

      result = github_importer.execute(access_params, :github)

      expect(Gitlab::InternalEvents).to have_received(:track_event).with(
        'enable_import_continuous_sync',
        hash_including(
          user: user,
          project: result[:project],
          namespace: group,
          additional_properties: { label: 'github' }
        )
      ).once
    end

    it 'points the project to the user credential' do
      result = github_importer.execute(access_params, :github)

      expect(result[:project].import_data.data).to include('user_credential_id' => user_credential.id)
    end

    it 'keeps the user credential next to the refresh credentials' do
      access_params.merge!(refresh_token: 'ghr_token', expires_at: 1.hour.from_now.to_i)

      result = github_importer.execute(access_params, :github)

      expect(result[:project].import_data.data).to include('user_credential_id' => user_credential.id)
      expect(result[:project].import_data.credentials).to include(refresh_token: 'ghr_token')
    end

    it 'ignores import data passed in the params' do
      params[:import_data] = { data: { user_credential_id: non_existing_record_id } }

      result = github_importer.execute(access_params, :github)

      expect(result[:project].import_data.data).to include('user_credential_id' => user_credential.id)
    end

    shared_examples 'fails without a user credential' do
      it 'returns an error and does not create the project' do
        result = nil

        expect { result = github_importer.execute(access_params, :github) }.not_to change { Project.count }

        expect(result).to include(
          status: :error,
          http_status: :unprocessable_entity,
          message: s_('GithubImport|To import with updates on, authorize GitHub again.')
        )
      end
    end

    context 'when the user has no credential' do
      let!(:user_credential) { nil }

      it_behaves_like 'fails without a user credential'
    end

    context 'when the credential belongs to another GitHub account' do
      let!(:user_credential) { create(:import_user_credential, user: user, provider_account_xid: 1) }

      it_behaves_like 'fails without a user credential'
    end

    context 'when the credential belongs to another user' do
      let!(:user_credential) { create(:import_user_credential, provider_account_xid: 583231) }

      it_behaves_like 'fails without a user credential'
    end

    context 'when the credential is for another GitHub host' do
      let!(:user_credential) do
        create(:import_user_credential, user: user, provider_account_xid: 583231, provider_host: 'ghe.example.com')
      end

      it_behaves_like 'fails without a user credential'
    end

    it 'creates the sync repository when GitHub returns a real Sawyer::Resource for the account' do
      agent = Sawyer::Agent.new('')
      allow(client).to receive_message_chain(:octokit, :user).and_return(Sawyer::Resource.new(agent, github_account))

      result = github_importer.execute(access_params, :github)

      expect(result).to include(status: :success)
      expect(result[:project].import_sync_repository).to have_attributes(
        provider_account_xid: 583231,
        provider_account_login: 'octocat',
        provider_repository_xid: 1296269,
        provider_repository_node_id: 'MDEwOlJlcG9zaXRvcnkxMjk2MjY5'
      )
    end

    context 'when the GitHub account lookup fails' do
      before do
        allow(client).to receive_message_chain(:octokit, :user)
          .and_raise(Octokit::Unauthorized.new(status: 401, body: 'Bad credentials'))
      end

      it 'returns a GitHub error and does not create the project' do
        result = nil

        expect { result = github_importer.execute(access_params, :github) }.not_to change { Project.count }

        expect(result).to include(
          status: :error,
          http_status: :unprocessable_entity,
          message: s_('GithubImport|Import failed because of a GitHub error: Bad credentials (HTTP 401)')
        )
      end
    end

    context 'when the sync repository is invalid' do
      let(:github_account) { { id: 583231, login: '' } }

      it 'does not track that continuous sync was enabled' do
        expect { github_importer.execute(access_params, :github) }
          .not_to trigger_internal_events('enable_import_continuous_sync')
      end

      it 'returns an error and creates neither the project nor the sync repository' do
        result = nil

        expect { result = github_importer.execute(access_params, :github) }
          .to not_change { Project.count }.and not_change { Import::Sync::Repository.count }

        expect(result).to include(
          status: :error,
          http_status: :unprocessable_entity,
          message: "Import sync repository provider account login can't be blank"
        )
      end
    end

    context 'when continuous sync is not checked' do
      let(:optional_stages) { { continuous_sync: 'false' } }

      it_behaves_like 'creates the project without continuous sync', :github
    end

    context 'when the github_continuous_import feature flag is disabled' do
      before do
        stub_feature_flags(github_continuous_import: false)
      end

      it_behaves_like 'creates the project without continuous sync', :github
    end

    context 'when the provider is Gitea' do
      it_behaves_like 'creates the project without continuous sync', :gitea
    end
  end

  def size_limit_error(repository_name, repository_size, limit)
    {
      status: :error,
      http_status: :unprocessable_entity,
      message: format(
        s_('GithubImport|"%{repository_name}" size (%{repository_size}) is larger than the limit of %{limit}.'),
        repository_name: repository_name,
        repository_size: ActiveSupport::NumberHelper.number_to_human_size(repository_size),
        limit: ActiveSupport::NumberHelper.number_to_human_size(limit))
    }
  end
end
