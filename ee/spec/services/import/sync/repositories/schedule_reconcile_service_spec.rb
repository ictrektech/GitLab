# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ScheduleReconcileService, feature_category: :importers do
  let(:repository) { create(:import_sync_repository, :oauth, authority_state: :provider_canonical) }
  let!(:source_state) do
    create(:import_sync_repository_state, repository: repository, domain: :source, state: :current)
  end

  let!(:work_items_state) do
    create(:import_sync_repository_state, repository: repository, domain: :work_items, state: :current)
  end

  let(:event_at) { Time.zone.parse('2026-08-25 12:00:00') }

  subject(:service) do
    described_class.new(repository, domains: %i[source work_items], event_at: event_at)
  end

  it 'atomically advances each requested domain and marks it pending' do
    expect(service.execute.payload[:desired_generations]).to eq('source' => 1, 'work_items' => 1)

    expect(source_state.reload).to have_attributes(
      desired_generation: 1,
      synced_generation: 0,
      state: 'pending',
      last_event_at: event_at
    )
    expect(work_items_state.reload).to have_attributes(
      desired_generation: 1,
      synced_generation: 0,
      state: 'pending',
      last_event_at: event_at
    )
  end

  it 'returns the application generation captured under the lock' do
    repository.update!(application_generation: 4)

    response = service.execute

    expect(response).to be_success
    expect(response.payload[:application_generation]).to eq(4)
  end

  it 'does not regress the last provider activity time' do
    source_state.update!(last_event_at: event_at + 1.minute)

    described_class.new(repository, domains: [:source], event_at: event_at).execute

    expect(source_state.reload.last_event_at).to eq(event_at + 1.minute)
  end

  it 'leaves the last provider activity time alone when no event time is given' do
    source_state.update!(last_event_at: event_at)

    described_class.new(repository, domains: [:source]).execute

    expect(source_state.reload).to have_attributes(desired_generation: 1, last_event_at: event_at)
  end

  it 'preserves an explicit pause while recording new desired work' do
    source_state.update!(state: :paused)

    described_class.new(repository, domains: [:source], event_at: event_at).execute

    expect(source_state.reload).to have_attributes(desired_generation: 1, state: 'paused')
  end

  it 'preserves a disconnected domain while recording new desired work' do
    source_state.update!(state: :disconnected)

    described_class.new(repository, domains: [:source], event_at: event_at).execute

    expect(source_state.reload).to have_attributes(desired_generation: 1, state: 'disconnected')
  end

  it 'keeps a running domain running so a failing pass can still record its failure' do
    source_state.update!(state: :running)

    described_class.new(repository, domains: [:source], event_at: event_at).execute

    expect(source_state.reload).to have_attributes(desired_generation: 1, synced_generation: 0, state: 'running')
  end

  it 'rejects unknown domains before writing' do
    expect { described_class.new(repository, domains: [:bogus]).execute }
      .to raise_error(ArgumentError, /Unknown import sync domain: bogus/)
  end

  it 'creates a missing state row before advancing it' do
    work_items_state.delete

    expect(service.execute.payload[:desired_generations]).to eq('source' => 1, 'work_items' => 2)

    expect(repository.sync_states.find_by!(domain: :work_items))
      .to have_attributes(desired_generation: 2, synced_generation: 0, state: 'pending')
  end

  it 'admits a provisioning repository' do
    repository.update!(authority_state: :provisioning)

    expect(service.execute.payload[:desired_generations]).to eq('source' => 1, 'work_items' => 1)
  end

  context 'when GitHub is not the active authority' do
    where(:authority_state) do
      [[:gitlab_canonical], [:bootstrap_canceled], [:cutover_failed], [:cutting_over]]
    end

    with_them do
      it 'refuses to schedule provider work and writes nothing' do
        repository.update!(authority_state: authority_state)

        expect { service.execute }.to raise_error(
          Import::Sync::Errors::InactiveAuthorityError,
          'GitHub updates are no longer active for this project'
        )
        expect(source_state.reload.desired_generation).to eq(0)
        expect(work_items_state.reload.desired_generation).to eq(0)
      end
    end
  end
end
