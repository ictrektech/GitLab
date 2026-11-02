# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::StartCatchUpService, feature_category: :importers do
  let(:repository) { create(:import_sync_repository, :oauth, authority_state: authority_state) }
  let(:lease_context) { instance_double(Import::Sync::Repositories::ApplicationLease::Context, verify!: true) }
  let(:lease) { instance_double(Import::Sync::Repositories::ApplicationLease) }

  subject(:service) { described_class.new(repository) }

  before do
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).with(repository.id).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
  end

  context 'when the bootstrap importer has just completed' do
    let(:authority_state) { :provisioning }

    it 'activates provider application' do
      expect(service.execute).to be(true)

      expect(repository.reload).to be_provider_canonical
    end

    it 'leaves enqueueing the first reconcile to the finish stage' do
      expect(Import::Sync::Repositories::ReconcileWorker).not_to receive(:perform_async)

      service.execute
    end

    it 'does not flip when the lease is lost' do
      allow(lease_context).to receive(:verify!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      expect { service.execute }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(repository.reload).to be_provisioning
    end

    it 'verifies the lease before taking the row lock' do
      expect(lease_context).to receive(:verify!).ordered.and_return(true)
      expect(repository).to receive(:with_lock).ordered.and_call_original

      service.execute
    end

    it 'lets lease contention propagate without flipping' do
      allow(lease).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

      expect { service.execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

      expect(repository.reload).to be_provisioning
    end

    it 'logs the transition with ids only' do
      expect(Gitlab::GithubImport::Logger).to receive(:info).with(
        message: 'import sync repository authority changed',
        import_sync_repository_id: repository.id,
        Labkit::Fields::GL_PROJECT_ID => repository.project_id,
        from: 'provisioning',
        to: 'provider_canonical'
      )

      service.execute
    end

    it 'does not create state rows' do
      expect { service.execute }.not_to change { Import::Sync::RepositoryState.count }
    end
  end

  context 'when the repository is already provider canonical' do
    let(:authority_state) { :provider_canonical }

    it 'does not flip again but returns true' do
      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      2.times { expect(service.execute).to be(true) }

      expect(repository.reload).to be_provider_canonical
    end
  end

  context 'when the bootstrap was canceled' do
    let(:authority_state) { :bootstrap_canceled }

    it 'returns false and leaves the row untouched' do
      expect(service.execute).to be(false)

      expect(repository.reload).to be_bootstrap_canceled
    end
  end

  context 'when updates have already stopped' do
    let(:authority_state) { :gitlab_canonical }

    it 'does not reactivate the project' do
      expect(service.execute).to be(false)

      expect(repository.reload).to be_gitlab_canonical
    end
  end

  context 'when the repository is disconnected' do
    let(:repository) { create(:import_sync_repository, :oauth, :disconnected) }

    it 'returns false and leaves the row untouched' do
      expect(service.execute).to be(false)

      expect(repository.reload).to be_disconnected
    end
  end

  context 'when the repository is cutting over or its cut-over failed' do
    where(:authority_state) { [[:cutting_over], [:cutover_failed]] }

    with_them do
      it 'returns false and leaves the row untouched' do
        expect(service.execute).to be(false)

        expect(repository.reload.authority_state).to eq(authority_state.to_s)
      end
    end
  end
end
