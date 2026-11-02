# frozen_string_literal: true

require 'spec_helper'

# Protects independent per-domain health and monotonic generation progress. The
# examples write only model fixtures; failures indicate unsafe coalescing or
# cross-project state that could conceal a lagging synchronization domain.
RSpec.describe Import::Sync::RepositoryState, feature_category: :importers do
  subject(:sync_state) { build(:import_sync_repository_state) }

  describe 'associations' do
    it 'defines the parent repository association' do
      is_expected.to belong_to(:repository)
        .class_name('Import::Sync::Repository')
        .required
        .inverse_of(:sync_states)
    end
  end

  describe 'sharding key' do
    let_it_be(:repository) { create(:import_sync_repository) }

    subject(:sync_state) do
      build(:import_sync_repository_state, repository: repository, project_id: nil)
    end

    it { is_expected.to populate_sharding_key(:project_id).with(repository.project_id) }
  end

  describe 'enums' do
    it 'defines independent synchronization domains' do
      is_expected.to define_enum_for(:domain)
        .with_values(inventory: 0, source: 1, work_items: 2)
        .with_prefix
    end

    it 'defines the domain health states' do
      is_expected.to define_enum_for(:state).with_values(
        pending: 0,
        running: 1,
        current: 2,
        delayed: 3,
        degraded: 4,
        paused: 5,
        disconnected: 6
      )
    end
  end

  describe 'validations' do
    it 'requires a nonnegative integer desired generation' do
      is_expected.to validate_numericality_of(:desired_generation)
        .only_integer
        .is_greater_than_or_equal_to(0)
    end

    it 'requires a nonnegative integer synced generation' do
      is_expected.to validate_numericality_of(:synced_generation)
        .only_integer
        .is_greater_than_or_equal_to(0)
    end

    it { is_expected.to validate_length_of(:cursor).is_at_most(2048).allow_nil }
    it { is_expected.to validate_length_of(:last_error_code).is_at_most(255).allow_nil }
    it { is_expected.to validate_length_of(:last_error_message).is_at_most(1024).allow_nil }

    it 'rejects duplicate domains for one provider repository' do
      existing = create(:import_sync_repository_state)
      duplicate = build(
        :import_sync_repository_state,
        repository: existing.repository,
        domain: existing.domain
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:domain]).to include('has already been taken')
    end

    it 'rejects a repository from another project' do
      sync_state.project_id = create(:project).id

      expect(sync_state).not_to be_valid
      expect(sync_state.errors[:repository]).to include('must belong to the same project.')
    end

    it 'rejects synced progress beyond the requested generation' do
      sync_state.desired_generation = 2
      sync_state.synced_generation = 3

      expect(sync_state).not_to be_valid
      expect(sync_state.errors[:synced_generation]).to include('must not exceed the desired generation.')
    end

    it 'skips the generation-order check when either generation is missing' do
      sync_state.desired_generation = nil
      sync_state.synced_generation = 3
      sync_state.validate

      expect(sync_state.errors[:synced_generation]).not_to include('must not exceed the desired generation.')
    end
  end

  describe '#lagging?' do
    it 'reports pending requested generations independently of the display state' do
      sync_state.desired_generation = 3
      sync_state.synced_generation = 2

      expect(sync_state).to be_lagging

      sync_state.synced_generation = 3

      expect(sync_state).not_to be_lagging
    end
  end
end
