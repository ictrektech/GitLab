# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::RequestUpdateService, feature_category: :importers do
  let(:repository) do
    create(:import_sync_repository, :oauth, authority_state: :provider_canonical, application_generation: 3)
  end

  let(:sync_states) { repository.sync_states.index_by(&:domain) }
  let(:event_at) { Time.zone.parse('2026-08-25 14:00:00') }

  subject(:service) { described_class.new(repository, event_at: event_at) }

  before do
    Import::Sync::RepositoryState.domains.each_key do |domain|
      create(:import_sync_repository_state, repository: repository, domain: domain, state: :current)
    end
    allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
  end

  it 'uses the shared scheduler and queues the captured application generation once' do
    expect(service.execute).to eq(3)

    expect(Import::Sync::Repositories::ReconcileWorker)
      .to have_received(:perform_async).with(repository.id, 3).once

    expect(sync_states.keys).to match_array(%w[inventory source work_items])
    sync_states.each_value do |sync_state|
      expect(sync_state.reload).to have_attributes(
        desired_generation: 1,
        synced_generation: 0,
        state: 'pending',
        last_event_at: event_at
      )
    end
  end

  it 'does not advance the last provider activity time when no event time is given' do
    expect { described_class.new(repository, event_at: nil).execute }
      .not_to change { repository.sync_states.pluck(:last_event_at) }
  end

  it 'does not queue work after GitHub updates have stopped' do
    repository.update!(authority_state: :gitlab_canonical)

    expect { service.execute }.to raise_error(Import::Sync::Errors::InactiveAuthorityError)

    expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
  end

  it 'does not queue work while the repository is disconnected' do
    repository.update!(
      authority_state: :disconnected,
      disconnect_reason: :repository_access_removed,
      restore_authority_state: :provider_canonical
    )

    expect { service.execute }.to raise_error(Import::Sync::Errors::InactiveAuthorityError)

    expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
  end
end
