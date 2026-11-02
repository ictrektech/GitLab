# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::StopCleanupWorker, feature_category: :importers do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:project) do
    create(:project, :import_finished, import_type: 'github', import_url: 'https://github.com/octocat/hello-world.git')
  end

  let(:authority_state) { :gitlab_canonical }
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: project,
      authority_state: authority_state,
      application_generation: 4,
      provider_webhook_xid: 42,
      webhook_secret: 'webhook-secret'
    )
  end

  let(:calls) { [] }
  let(:hook_error) { nil }
  let(:lock_key) { "import_sync:repository:#{repository.id}:webhook" }

  # Records the removal as the real DELETE, so the order check does not depend on how the project is loaded.
  let!(:removal_subscriber) do
    ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      calls << [:remove_import_data] if payload[:sql].start_with?('DELETE FROM "project_import_data"')
    end
  end

  subject(:worker) { described_class.new }

  before do
    project.build_or_assign_import_data(credentials: { user: 'token' }).save!

    # The GitHub boundary: a real client built by Authentication, with only its delete_hook call recorded.
    allow(Gitlab::GithubImport).to receive(:new_client_for).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do |client|
        allow(client).to receive(:delete_hook) do |repository_xid, hook_xid|
          calls << [:delete_hook, repository_xid, hook_xid]
          raise hook_error if hook_error
        end
      end
    end

    allow(Gitlab::GithubImport::Logger).to receive(:warn)
    allow(Gitlab::GithubImport::Logger).to receive(:info)
  end

  after do
    ActiveSupport::Notifications.unsubscribe(removal_subscriber)
  end

  def hook_calls
    calls.select { |call| call.first == :delete_hook }
  end

  it 'retries five times and does not go to the dead set' do
    expect(described_class.get_sidekiq_options).to include('retry' => 5, 'dead' => false)
  end

  it 'holds its deduplication lock until the job finishes and never reschedules' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).not_to include(:if_deduplicated, :including_scheduled)
  end

  it 'is an idempotent worker with external dependencies and sticky data consistency' do
    expect(described_class).to be_idempotent
    expect(described_class).to be_worker_has_external_dependencies
    expect(described_class.get_data_consistency_per_database.values).to all(eq(:sticky))
  end

  it 'shares the GitHub import concurrency limit' do
    stub_application_setting(import_jobs_concurrency_limit: 7)

    expect(described_class.get_concurrency_limit).to eq(7)
  end

  describe '.sidekiq_retries_exhausted' do
    let(:error) { Octokit::InternalServerError.new }

    def exhaust(repository_id = repository.id)
      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [repository_id] }, error)
    end

    it 'tracks the exhausted job with the repository id only' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(error, import_sync_repository_id: repository.id)

      exhaust
    end

    it 'clears the hook record and removes the import data #security' do
      exhaust

      expect(hook_calls).to be_empty
      expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      expect(project.reload.import_data).to be_nil
    end

    context 'when the row was released after an unfinished import' do
      let(:authority_state) { :bootstrap_canceled }

      it 'clears the hook record and removes the import data #security' do
        exhaust

        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
        expect(project.reload.import_data).to be_nil
      end
    end

    context 'when the stop did not complete' do
      let(:authority_state) { :cutting_over }

      it 'leaves the hook record and the import data alone #security' do
        exhaust

        expect(repository.reload).to have_attributes(provider_webhook_xid: 42, webhook_secret: 'webhook-secret')
        expect(project.reload.import_data).to be_present
      end
    end

    it 'does nothing for a missing repository' do
      expect { exhaust(non_existing_record_id) }.not_to raise_error

      expect(project.reload.import_data).to be_present
    end
  end

  describe '.remove_import_data' do
    it 'removes the import data of the project' do
      described_class.remove_import_data(repository)

      expect(project.reload.import_data).to be_nil
    end

    it 'does nothing when the project no longer exists' do
      missing = build(:import_sync_repository, project_id: non_existing_record_id)

      expect { described_class.remove_import_data(missing) }.not_to change { ProjectImportData.count }
    end
  end

  describe '#perform' do
    it 'deletes the hook, then removes the import data, in that order #security' do
      worker.perform(repository.id)

      expect(calls).to eq([[:delete_hook, repository.provider_repository_xid, 42], [:remove_import_data]])
      expect(Gitlab::GithubImport).to have_received(:new_client_for).once.with(project, token: 'token', parallel: true)
      expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      expect(project.reload.import_data).to be_nil
    end

    it 'logs one info line with the ids only' do
      worker.perform(repository.id)

      expect(Gitlab::GithubImport::Logger).to have_received(:info).once.with(
        message: 'import sync cleanup after stop finished',
        import_sync_repository_id: repository.id,
        Labkit::Fields::GL_PROJECT_ID => project.id
      )
    end

    context 'when the hook deletion fails' do
      where(:error_class) do
        [
          [Octokit::InternalServerError],
          [Gitlab::GithubImport::RateLimitError],
          [Octokit::UnprocessableEntity],
          [Faraday::ConnectionFailed]
        ]
      end

      with_them do
        let(:hook_error) { error_class.new }

        it 'raises for a retry and keeps the token and the hook record so the deletion can be retried #security' do
          expect { worker.perform(repository.id) }.to raise_error(error_class)

          expect(calls).to eq([[:delete_hook, repository.provider_repository_xid, 42]])
          expect(repository.reload).to have_attributes(provider_webhook_xid: 42, webhook_secret: 'webhook-secret')
          expect(project.reload.import_data).to be_present
        end
      end
    end

    context 'when the import data is already gone, as for a released disconnected row' do
      let(:authority_state) { :bootstrap_canceled }

      before do
        project.import_data.destroy!
      end

      it 'clears the hook record without a GitHub call or a retry and finishes the cleanup' do
        expect { worker.perform(repository.id) }.not_to raise_error

        expect(Gitlab::GithubImport).not_to have_received(:new_client_for)
        expect(hook_calls).to be_empty
        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
        expect(Gitlab::GithubImport::Logger).to have_received(:info)
          .with(hash_including(message: 'import sync cleanup after stop finished'))
      end
    end

    context 'when the token is missing' do
      before do
        project.import_data.update!(credentials: {})
      end

      it 'clears the hook record without a GitHub call and removes the import data' do
        expect { worker.perform(repository.id) }.not_to raise_error

        expect(hook_calls).to be_empty
        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
        expect(project.reload.import_data).to be_nil
      end
    end

    # The hook is already gone (404), or the token can no longer see it (401, 403): none is a failed attempt.
    context 'when GitHub does not find the hook or refuses the token' do
      where(:error_class) { [[Octokit::NotFound], [Octokit::Unauthorized], [Octokit::Forbidden]] }

      with_them do
        let(:hook_error) { error_class.new }

        it 'is not an error and clears the hook record' do
          expect { worker.perform(repository.id) }.not_to raise_error

          expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
          expect(project.reload.import_data).to be_nil
        end
      end
    end

    context 'when no hook is recorded' do
      before do
        repository.update!(provider_webhook_xid: nil, webhook_secret: nil)
      end

      it 'makes no GitHub call and removes the import data' do
        worker.perform(repository.id)

        expect(Gitlab::GithubImport).not_to have_received(:new_client_for)
        expect(hook_calls).to be_empty
        expect(project.reload.import_data).to be_nil
      end
    end

    context 'when the webhook lease is held', :clean_gitlab_redis_shared_state do
      before do
        Gitlab::ExclusiveLease.new(lock_key, timeout: 1.minute).try_obtain
      end

      it 'raises for a retry and keeps the import data' do
        expect { worker.perform(repository.id) }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

        expect(hook_calls).to be_empty
        expect(repository.reload.provider_webhook_xid).to eq(42)
        expect(project.reload.import_data).to be_present
      end
    end

    context 'when the stop did not complete' do
      where(:state, :extra_attributes) do
        :provider_canonical | {}
        :cutting_over | {}
        :cutover_failed | {}
        :provisioning | {}
        :disconnected | { disconnect_reason: :token_revoked, restore_authority_state: :provider_canonical }
      end

      with_them do
        let(:repository) do
          create(
            :import_sync_repository,
            :oauth,
            project: project,
            authority_state: state,
            provider_webhook_xid: 42,
            webhook_secret: 'webhook-secret',
            **extra_attributes
          )
        end

        it 'makes no GitHub call and leaves the import data and the hook record alone #security' do
          worker.perform(repository.id)

          expect(Gitlab::GithubImport).not_to have_received(:new_client_for)
          expect(calls).to be_empty
          expect(project.reload.import_data).to be_present
          expect(repository.reload).to have_attributes(authority_state: state.to_s, provider_webhook_xid: 42)
        end
      end

      it 'does nothing for a missing repository' do
        expect { worker.perform(non_existing_record_id) }.not_to raise_error

        expect(calls).to be_empty
        expect(project.reload.import_data).to be_present
      end
    end

    describe 'authority state and generation' do
      where(:hook_error_class) do
        [[nil], [Octokit::NotFound]]
      end

      with_them do
        let(:hook_error) { hook_error_class&.new }

        it 'never writes the authority state or the generation #security' do
          repository

          recorder = ActiveRecord::QueryRecorder.new { worker.perform(repository.id) }
          updates = recorder.log.grep(/\AUPDATE "import_sync_repositories"/)

          expect(updates).to all(match(/"provider_webhook_xid"/))
          expect(updates).not_to include(match(/"authority_state"|"application_generation"/))
          expect(repository.reload).to have_attributes(authority_state: 'gitlab_canonical', application_generation: 4)
        end
      end

      it 'leaves the authority state and the generation alone when the credentials are missing' do
        project.import_data.destroy!

        worker.perform(repository.id)

        expect(repository.reload).to have_attributes(authority_state: 'gitlab_canonical', application_generation: 4)
      end
    end

    context 'when the row was released after an unfinished import' do
      let(:authority_state) { :bootstrap_canceled }

      it 'deletes the hook, then removes the import data, in that order #security' do
        worker.perform(repository.id)

        expect(calls).to eq([[:delete_hook, repository.provider_repository_xid, 42], [:remove_import_data]])
        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      end
    end

    context 'when the project was loaded while the row still looked provider_canonical' do
      let(:authority_state) { :provider_canonical }

      # With no recorded hook, disable (which reloads the repository) does not run, so only the worker's own
      # fresh load keeps this from acting on the stale cached project.
      it 'removes the import data from a freshly loaded project #security' do
        repository.update!(provider_webhook_xid: nil, webhook_secret: nil)
        repository_id = repository.id
        stale_project = Project.find(project.id)
        stale_project.import_sync_repository
        stale_repository = Import::Sync::Repository.find(repository_id)
        stale_repository.association(:project).target = stale_project

        Import::Sync::Repository.find(repository_id).update!(authority_state: :gitlab_canonical)
        stale_repository.authority_state = :gitlab_canonical
        allow(Import::Sync::Repository).to receive(:find_by_id).with(repository_id).and_return(stale_repository)

        expect { stale_project.remove_import_data }.not_to change { ProjectImportData.count }

        worker.perform(repository.id)

        expect(project.reload.import_data).to be_nil
      end
    end

    context 'when the project is a mirror' do
      let(:project) { create(:project, :mirror, :import_finished) }

      it 'keeps the import data and still attempts the hook deletion' do
        worker.perform(repository.id)

        expect(hook_calls.size).to eq(1)
        expect(project.reload.import_data).to be_present
        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [repository.id] }

      it 'makes one GitHub call and changes nothing on the second run' do
        perform_idempotent_work

        expect(calls).to eq([[:delete_hook, repository.provider_repository_xid, 42], [:remove_import_data]])
        expect(repository.reload).to have_attributes(
          authority_state: 'gitlab_canonical',
          application_generation: 4,
          provider_webhook_xid: nil,
          webhook_secret: nil
        )
        expect(project.reload.import_data).to be_nil
      end
    end
  end
end
