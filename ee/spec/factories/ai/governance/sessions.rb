# frozen_string_literal: true

FactoryBot.define do
  factory :ai_governance_session, class: 'Ai::Governance::Session' do
    # Forced to :create so build(:ai_governance_session) still populates namespace_id and
    # user_id: FactoryBot mirrors the parent's build strategy by default, which would
    # otherwise leave both ids nil until the session itself is saved.
    association :namespace, strategy: :create
    association :user, strategy: :create
    session_started_at { Time.current }
    # No FK on workflow_id (see ignored_fk_columns_map), so a plain sequence is enough to
    # satisfy ExactlyOnePresentValidator without creating a real Workflow row per example.
    sequence(:workflow_id)

    trait :external do
      workflow_id { nil }
      source { :claude_code_compliance_api }
      sequence(:external_xid) { |n| "clls_#{n}" }
    end

    # MCP carries no session identifier, so GitLab mints the xid itself.
    trait :mcp do
      workflow_id { nil }
      source { :mcp }
      external_xid { SecureRandom.uuid }
    end
  end
end
