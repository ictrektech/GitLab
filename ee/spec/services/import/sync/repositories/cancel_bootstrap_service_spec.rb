# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::CancelBootstrapService, feature_category: :importers do
  include ExclusiveLeaseHelpers

  let(:from) { %w[provisioning] }

  subject(:execute) { described_class.new(repository, from: from).execute }

  context 'when the repository is provisioning' do
    let(:repository) { create(:import_sync_repository, :oauth) }

    it 'moves it to bootstrap_canceled and returns the previous state' do
      expect(execute).to eq('provisioning')
      expect(repository.reload).to be_bootstrap_canceled
    end

    it 'only cancels provisioning by default' do
      expect(described_class.new(repository).execute).to eq('provisioning')
    end

    it 'raises and leaves the row alone when the lease is held' do
      stub_exclusive_lease_taken(Import::Sync::Repositories::ApplicationLease.key(repository.id))

      expect { execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      expect(repository.reload).to be_provisioning
    end

    it 're-checks the state under the lock and leaves a row that changed after the read' do
      Import::Sync::Repository.find(repository.id).update!(authority_state: :gitlab_canonical)

      expect(execute).to be_nil
      expect(repository.reload).to be_gitlab_canonical
    end
  end

  context 'when the repository is provider_canonical' do
    let(:repository) { create(:import_sync_repository, :oauth, authority_state: :provider_canonical) }

    it 'leaves it untouched unless provider_canonical is allowed' do
      expect(execute).to be_nil
      expect(repository.reload).to be_provider_canonical
    end

    context 'when provider_canonical is allowed' do
      let(:from) { %w[provisioning provider_canonical] }

      it 'moves it to bootstrap_canceled and returns the previous state' do
        expect(execute).to eq('provider_canonical')
        expect(repository.reload).to be_bootstrap_canceled
      end
    end
  end

  context 'without a repository' do
    let(:repository) { nil }

    it { is_expected.to be_nil }
  end
end
