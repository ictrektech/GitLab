# frozen_string_literal: true

FactoryBot.define do
  # Builds one per-domain generation and health record. The project is
  # inherited from the repository to exercise production sharding behavior.
  factory :import_sync_repository_state, class: 'Import::Sync::RepositoryState' do
    repository { association(:import_sync_repository) }
    project_id { repository.project_id }
    domain { :source }
    state { :pending }
    desired_generation { 0 }
    synced_generation { 0 }
  end
end
