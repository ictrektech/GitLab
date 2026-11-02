# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReleaseUnfinishedImportWorker, feature_category: :importers do
  include ExclusiveLeaseHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:project) { create(:project, :import_started, import_type: 'github') }

  subject(:worker) { described_class.new }

  before do
    allow(Import::Sync::Repositories::StopCleanupWorker).to receive(:perform_async)
  end

  it 'defers on the tables it writes' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org,
      tables: [:import_sync_repositories]
    )
  end

  context 'when the sync repository is provisioning' do
    let!(:sync_repository) { create(:import_sync_repository, :oauth, project: project) }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id] }

      it 'cancels the sync repository and logs one warning without recording a failure' do
        expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
          Labkit::Fields::LOG_MESSAGE => 'Continuous sync was not enabled because the import did not finish',
          Labkit::Fields::GL_PROJECT_ID => project.id,
          import_sync_repository_id: sync_repository.id,
          import_status: 'started',
          previous_authority_state: 'provisioning'
        ).once

        perform_idempotent_work

        expect(sync_repository.reload).to be_bootstrap_canceled
        expect(project.import_failures).to be_empty
        expect(project.import_state.reload.status).to eq('started')
        expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
      end
    end
  end

  context 'when the sync repository is provider_canonical' do
    let!(:sync_repository) do
      create(
        :import_sync_repository, :oauth,
        project: project, authority_state: :provider_canonical, provider_webhook_xid: 42
      )
    end

    before do
      project.import_state.update_column(:status, 'failed')
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id] }

      it 'cancels the sync repository, enqueues the cleanup and logs one warning' do
        expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
          Labkit::Fields::LOG_MESSAGE => 'Continuous sync was stopped because the import did not finish',
          Labkit::Fields::GL_PROJECT_ID => project.id,
          import_sync_repository_id: sync_repository.id,
          import_status: 'failed',
          previous_authority_state: 'provider_canonical'
        ).once

        perform_idempotent_work

        expect(sync_repository.reload).to be_bootstrap_canceled
        expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async)
          .with(sync_repository.id).at_least(:once)
      end
    end

    it 're-enqueues the cleanup without logging again when a run lost the enqueue after the move' do
      sync_repository.update!(authority_state: :bootstrap_canceled)

      expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

      worker.perform(project.id)

      expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(sync_repository.id)
    end

    it 're-enqueues the cleanup while the import data remains, even without a hook' do
      sync_repository.update!(authority_state: :bootstrap_canceled, provider_webhook_xid: nil)
      project.build_or_assign_import_data(credentials: { user: 'token' }).save!

      worker.perform(project.id)

      expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(sync_repository.id)
    end

    it 'releases a row that StartCatchUpService flipped after the hook saw it provisioning' do
      sync_repository.update!(authority_state: :provisioning)
      Import::Sync::Repositories::StartCatchUpService.new(sync_repository).execute

      worker.perform(project.id)

      expect(sync_repository.reload).to be_bootstrap_canceled
      expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(sync_repository.id)
    end

    it 'raises for a retry and leaves the row alone when the lease is held' do
      stub_exclusive_lease_taken(Import::Sync::Repositories::ApplicationLease.key(sync_repository.id))

      expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

      expect { worker.perform(project.id) }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

      expect(sync_repository.reload).to be_provider_canonical
      expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
    end
  end

  context 'when the sync repository is disconnected' do
    it 'cancels the row, clears the disconnect fields and enqueues the cleanup of its hook record' do
      project.import_state.update_column(:status, 'failed')
      sync_repository = create(
        :import_sync_repository, :oauth, :token_revoked, project: project, provider_webhook_xid: 42
      )

      worker.perform(project.id)

      expect(sync_repository.reload).to have_attributes(
        authority_state: 'bootstrap_canceled', disconnect_reason: nil, restore_authority_state: nil
      )
      expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(sync_repository.id)
    end
  end

  context 'when the import finished' do
    it 'leaves a provider_canonical row alone' do
      project.import_state.update_column(:status, 'finished')
      sync_repository = create(:import_sync_repository, :oauth, project: project, authority_state: :provider_canonical)

      worker.perform(project.id)

      expect(sync_repository.reload).to be_provider_canonical
      expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
    end
  end

  context 'when the sync repository is in a state the release never touches' do
    where(:state) { %i[cutting_over cutover_failed gitlab_canonical bootstrap_canceled] }

    with_them do
      it 'leaves the row alone' do
        sync_repository = create(:import_sync_repository, :oauth, project: project, authority_state: state)

        expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

        worker.perform(project.id)

        expect(sync_repository.reload.authority_state).to eq(state.to_s)
        expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
      end
    end
  end

  it 'does nothing without a sync repository' do
    expect(Gitlab::GithubImport::Logger).not_to receive(:warn)

    worker.perform(project.id)
  end

  it 'does nothing when the project no longer exists' do
    expect { worker.perform(non_existing_record_id) }.not_to raise_error
  end
end
