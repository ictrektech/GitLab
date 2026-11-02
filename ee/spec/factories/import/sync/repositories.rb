# frozen_string_literal: true

FactoryBot.define do
  factory :import_sync_repository, class: 'Import::Sync::Repository' do
    project { association(:project, skip_disk_validation: true) }
    connected_by_user { association(:user) }
    authority_state { :provisioning }
    application_generation { 0 }
    provider { :github }
    sequence(:provider_installation_xid, 20_000)
    sequence(:provider_account_xid, 10_000)
    sequence(:provider_account_login) { |n| "github-account-#{n}" }
    sequence(:provider_repository_xid, 30_000)
    sequence(:provider_repository_node_id) { |n| "R_#{n}" }
    sequence(:provider_full_name) { |n| "github-account/repository-#{n}" }
    provider_default_branch { 'main' }

    trait :oauth do
      provider_installation_xid { nil }
    end

    trait :disconnected do
      authority_state { :disconnected }
      disconnect_reason { :repository_access_removed }
      restore_authority_state { :provider_canonical }
    end

    trait :token_revoked do
      authority_state { :disconnected }
      disconnect_reason { :token_revoked }
      restore_authority_state { :provider_canonical }
    end
  end
end
