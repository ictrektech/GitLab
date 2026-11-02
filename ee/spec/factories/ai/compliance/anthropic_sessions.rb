# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compliance_anthropic_session, class: 'Ai::Compliance::Anthropic::Session' do
    namespace { association(:group) }
    anthropic_integration { association(:ai_compliance_anthropic_integration, namespace: namespace) }
    ai_governance_session do
      association(:ai_governance_session, :external, namespace: namespace, external_xid: session_xid)
    end
    sequence(:session_xid) { |n| "clls_01ABCDEF#{n}" }
  end
end
