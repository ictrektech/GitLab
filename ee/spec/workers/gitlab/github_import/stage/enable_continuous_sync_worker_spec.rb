# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Stage::EnableContinuousSyncWorker, feature_category: :importers do
  include ExclusiveLeaseHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:project) { create(:project, :import_started) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, parallel?: true, create_hook: { id: 42 }) }
  let(:callback_url) { "https://gitlab.example.com/api/v4/projects/#{project.id}/github/webhooks" }

  subject(:worker) { described_class.new }

  before do
    stub_config_setting(url: 'https://gitlab.example.com')
  end

  it_behaves_like Gitlab::GithubImport::StageMethods do
    let(:fail_import_on_exhaustion) { false }
  end

  it_behaves_like Import::ResumableImportJob

  describe '#import' do
    context 'when the sync repository is still provisioning' do
      let!(:sync_repository) { create(:import_sync_repository, :oauth, project: project) }

      it 'hands authority to GitHub and enqueues the finish stage, which enqueues the reconcile' do
        expect(Import::Sync::Repositories::ReconcileWorker).not_to receive(:perform_async)
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).once

        worker.import(client, project)

        expect(sync_repository.reload).to be_provider_canonical
      end

      it 'does not flip again on a second run' do
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

        worker.import(client, project)

        expect(Gitlab::GithubImport::Logger).not_to receive(:info)
          .with(hash_including(message: 'import sync repository authority changed'))

        worker.import(client, project.reload)

        expect(sync_repository.reload).to be_provider_canonical
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to have_received(:perform_async).twice
      end

      it 'enqueues the finish stage on retry when the first run flipped but failed to enqueue it' do
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).and_raise(Redis::BaseError)

        expect { worker.import(client, project) }.to raise_error(Redis::BaseError)
        expect(sync_repository.reload).to be_provider_canonical

        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).and_call_original
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)

        worker.import(client, project.reload)
      end

      it 'finishes the import when the service reports not eligible' do
        allow_next_instance_of(Import::Sync::Repositories::StartCatchUpService) do |service|
          allow(service).to receive(:execute).and_return(false)
        end

        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)
        expect(Gitlab::GithubImport::Logger).to receive(:info).with(
          hash_including(
            message: 'sync repository is provisioning, finishing without continuous sync',
            project_id: project.id
          )
        )

        worker.import(client, project)
      end

      it 'registers the GitHub webhook with the stage client and the project id callback URL' do
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)

        expect(Import::Sync::Github::Oauth::WebhookManagementService).to receive(:new)
          .with(sync_repository, client: client, callback_url: callback_url).and_call_original
        expect(client).to receive(:create_hook).with(
          sync_repository.provider_repository_xid, hash_including(url: callback_url), anything
        ).and_return({ id: 42 }).ordered
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).ordered

        worker.import(client, project)

        expect(sync_repository.reload).to have_attributes(provider_webhook_xid: 42, webhook_secret: be_present)
      end

      it 'does not register the webhook when the service reports not eligible' do
        allow_next_instance_of(Import::Sync::Repositories::StartCatchUpService) do |service|
          allow(service).to receive(:execute).and_return(false)
        end
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

        expect(Import::Sync::Github::Oauth::WebhookManagementService).not_to receive(:new)

        worker.import(client, project)
      end

      it 'lets a webhook failure propagate so Sidekiq retries' do
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        allow(client).to receive(:create_hook).and_raise(Octokit::InternalServerError)

        expect(Gitlab::GithubImport::Stage::FinishImportWorker).not_to receive(:perform_async)

        expect { worker.import(client, project) }.to raise_error(Octokit::InternalServerError)
        expect(sync_repository.reload).to have_attributes(
          authority_state: 'provider_canonical',
          provider_webhook_xid: nil
        )
      end

      it 'lets a rate limit propagate to the stage rate limit handling' do
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        allow(client).to receive(:create_hook).and_raise(Gitlab::GithubImport::RateLimitError)

        expect { worker.import(client, project) }.to raise_error(Gitlab::GithubImport::RateLimitError)
      end

      context 'when GitHub rejects the webhook' do
        before do
          allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        end

        where(:error, :reason) do
          Octokit::Unauthorized | 'token_revoked'
          Octokit::Forbidden    | 'insufficient_scope'
        end

        with_them do
          it 'disconnects the sync repository and enqueues the finish stage' do
            allow(client).to receive(:create_hook).and_raise(error)

            expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)
            allow(Gitlab::GithubImport::Logger).to receive(:info)
            expect(Gitlab::GithubImport::Logger).to receive(:info).with(
              hash_including(
                message: 'could not create GitHub webhook, sync repository disconnected',
                disconnect_reason: reason,
                project_id: project.id
              )
            )

            worker.import(client, project)

            expect(sync_repository.reload).to have_attributes(
              authority_state: 'disconnected',
              disconnect_reason: reason,
              restore_authority_state: 'provider_canonical',
              provider_webhook_xid: nil
            )
          end
        end

        it 'leaves a repository that the service already disconnected untouched' do
          sync_repository.update!(
            consecutive_auth_failures: Import::Sync::Repository::MAX_CONSECUTIVE_AUTH_FAILURES - 1
          )
          allow(client).to receive(:create_hook).and_raise(Octokit::Unauthorized)
          allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

          worker.import(client, project)

          expect(sync_repository.reload).to have_attributes(
            authority_state: 'disconnected',
            disconnect_reason: 'token_revoked'
          )
        end

        it 'lets a secondary rate limit propagate instead of disconnecting' do
          allow(client).to receive(:create_hook).and_raise(Octokit::AbuseDetected)

          expect(Gitlab::GithubImport::Stage::FinishImportWorker).not_to receive(:perform_async)

          expect { worker.import(client, project) }.to raise_error(Octokit::AbuseDetected)
          expect(sync_repository.reload).to be_provider_canonical
        end
      end

      it 'lets lease contention propagate so Sidekiq retries' do
        allow_next_instance_of(Import::Sync::Repositories::StartCatchUpService) do |service|
          allow(service).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
        end

        expect(Gitlab::GithubImport::Stage::FinishImportWorker).not_to receive(:perform_async)

        expect { worker.import(client, project) }
          .to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end
    end

    context 'when a retry finds the sync repository already handed to GitHub without a webhook' do
      let!(:sync_repository) do
        create(:import_sync_repository, :oauth, project: project, authority_state: :provider_canonical)
      end

      it 'still registers the webhook' do
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

        expect(client).to receive(:create_hook).and_return({ id: 42 })

        worker.import(client, project)

        expect(sync_repository.reload.provider_webhook_xid).to eq(42)
      end

      it 'does not create a second webhook when one is already recorded' do
        sync_repository.update!(provider_webhook_xid: 42, webhook_secret: 'secret')
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

        expect(client).not_to receive(:create_hook)

        worker.import(client, project)
      end
    end

    context 'when the sync repository has already left provisioning' do
      let!(:sync_repository) do
        create(:import_sync_repository, :oauth, project: project, authority_state: :bootstrap_canceled)
      end

      it 'logs it, leaves the authority state untouched and enqueues the finish stage' do
        expect(Import::Sync::Github::Oauth::WebhookManagementService).not_to receive(:new)
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)
        expect(Gitlab::GithubImport::Logger).to receive(:info).with(
          hash_including(
            message: 'sync repository is bootstrap_canceled, finishing without continuous sync',
            project_id: project.id
          )
        )

        worker.import(client, project)

        expect(sync_repository.reload).to be_bootstrap_canceled
      end
    end

    context 'when the project has no sync repository' do
      it 'logs it and enqueues the finish stage without creating one' do
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)
        expect(Gitlab::GithubImport::Logger).to receive(:info).with(
          hash_including(
            message: 'no sync repository found, finishing without continuous sync',
            project_id: project.id,
            import_stage: described_class.name
          )
        )

        expect { worker.import(client, project) }.not_to change { Import::Sync::Repository.count }
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    it 'records a non-fatal failure and enqueues the finish stage' do
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)

      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))

      expect(project.import_state.reload.status).to eq('started')
      expect(project.import_failures.last).to have_attributes(
        exception_class: 'StandardError',
        source: described_class.name,
        retry_count: nil
      )
    end

    it 'cancels a sync repository that never left provisioning' do
      sync_repository = create(:import_sync_repository, :oauth, project: project)
      allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))

      expect(sync_repository.reload).to be_bootstrap_canceled
    end

    it 'leaves a sync repository that already took over untouched' do
      sync_repository = create(:import_sync_repository, :oauth, project: project, authority_state: :provider_canonical)
      allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)

      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))

      expect(sync_repository.reload).to be_provider_canonical
    end

    it 'does not overwrite a row that StartCatchUpService took over after the stale read' do
      sync_repository = create(:import_sync_repository, :oauth, project: project)
      stale_repository = Import::Sync::Repository.find(sync_repository.id)
      sync_repository.update!(authority_state: :provider_canonical)

      allow(Project).to receive(:find_by_id).and_call_original
      allow(Project).to receive(:find_by_id).with(project.id)
        .and_return(instance_double(Project, import_sync_repository: stale_repository))
      expect(stale_repository).to be_provisioning
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).once

      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))

      expect(sync_repository.reload).to be_provider_canonical
    end

    it 'tracks the failed failure recording, skips the cancel and still enqueues the finish stage once ' \
      'when the project no longer exists' do
      project_id = non_existing_record_id

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(ActiveRecord::RecordNotFound), hash_including(project_id: project_id)).once
      expect(Import::Sync::Repositories::ApplicationLease).not_to receive(:new)
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project_id).once

      expect do
        described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project_id] }, StandardError.new('boom'))
      end.not_to raise_error
    end

    it 'tracks a failed failure recording, still cancels and enqueues the finish stage once' do
      sync_repository = create(:import_sync_repository, :oauth, project: project)
      track_error = ActiveRecord::StatementInvalid.new('track failed')
      allow(Gitlab::Import::ImportFailureService).to receive(:track).and_raise(track_error)

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(track_error, hash_including(project_id: project.id)).once
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).once

      expect do
        described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))
      end.not_to raise_error
      expect(sync_repository.reload).to be_bootstrap_canceled
    end

    it 'tracks a failed cancel and still enqueues the finish stage once' do
      sync_repository = create(:import_sync_repository, :oauth, project: project)
      cancel_error = ActiveRecord::StatementInvalid.new('cancel failed')

      allow_next_found_instance_of(Import::Sync::Repository) do |repository|
        allow(repository).to receive(:update!).and_raise(cancel_error)
      end

      allow(Gitlab::ErrorTracking).to receive(:track_exception).and_call_original
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(cancel_error, hash_including(project_id: project.id)).once
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).once

      expect do
        described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))
      end.not_to raise_error

      expect(sync_repository.reload).to be_provisioning
    end

    it 'leaves the row alone, tracks the contention and enqueues the finish stage once when the lease is held' do
      sync_repository = create(:import_sync_repository, :oauth, project: project)
      stub_exclusive_lease_taken(Import::Sync::Repositories::ApplicationLease.key(sync_repository.id))

      allow(Gitlab::ErrorTracking).to receive(:track_exception).and_call_original
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError),
          hash_including(project_id: project.id)).once
      expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id).once

      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [project.id] }, StandardError.new('boom'))

      expect(sync_repository.reload).to be_provisioning
    end
  end
end
