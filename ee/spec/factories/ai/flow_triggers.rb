# frozen_string_literal: true

FactoryBot.define do
  factory :ai_flow_trigger, class: '::Ai::FlowTrigger' do
    project
    user factory: :service_account
    event_types { [::Ai::FlowTrigger::EVENT_TYPES[:mention]] }
    sequence(:description) { |n| "description #{n}" }
    sequence(:config_path) { |n| "path/#{n}.yml" }
    filter { {} }

    trait :inactive do
      active { false }
    end

    trait :with_goals do
      event_types { [::Ai::FlowTrigger::EVENT_TYPES[:assign]] }
      goals { { 'assign' => 'Triage this issue and add a severity label.' } }
    end

    trait :for_catalog_consumer do
      project { association(:project, :in_group) }
      config_path { nil }
      user { nil }
      ai_catalog_item_consumer { association(:ai_catalog_item_consumer, :child_item_consumer, project:) }
    end

    trait :for_inheritance_consumer do
      project { nil }
      group { association(:group) }
      config_path { nil }
      user { nil }
      ai_catalog_item_consumer { association(:ai_catalog_item_consumer, :inheritance, group:) }
    end

    # An autonomous trigger has to be catalog-backed with a provisioned account:
    # a config_path trigger would run as a caller-supplied user_id, with no human
    # to intersect its permissions against.
    trait :autonomous do
      for_catalog_consumer

      event_types { [::Ai::FlowTrigger::EVENT_TYPES[:scheduled]] }
      autonomous_service_account { association(:service_account, composite_identity_enforced: false) }
    end
  end
end
