# frozen_string_literal: true

FactoryBot.define do
  factory :incident_management_escalation_policy, class: 'IncidentManagement::EscalationPolicy' do
    association :project
    sequence :name do |n|
      "EscalationPolicy #{n}"
    end

    description { 'Policy description' }

    transient do
      rule_count { 1 }
    end

    rules do
      Array.new(rule_count) do
        association(:incident_management_escalation_rule, strategy: :build, policy: instance)
      end
    end
  end
end
