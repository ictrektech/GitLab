# frozen_string_literal: true

FactoryBot.define do
  factory :ai_catalog_item_consumer, class: 'Ai::Catalog::ItemConsumer' do
    for_agent
    enabled { true }
    locked { true }
    kind { :direct }
    project { association :project, :in_group if group.nil? && organization.nil? }
    service_account do
      if project.nil? && group&.root? && (item.flow? || item.third_party_flow?)
        association(:service_account, provisioned_by_group: group)
      end
    end

    trait :for_agent do
      item { association(:ai_catalog_agent, organization:) }
    end

    trait :for_flow do
      item { association(:ai_catalog_flow, organization:) }
    end

    trait :for_third_party_flow do
      item { association(:ai_catalog_third_party_flow, organization:) }
    end

    trait :child_item_consumer do
      for_flow

      parent_item_consumer do
        association(:ai_catalog_item_consumer, :parent_item_consumer, group: project.root_ancestor, item: item)
      end
    end

    trait :parent_item_consumer do
      for_flow

      group { association :group }

      service_account { association(:service_account, provisioned_by_group: group) }
    end

    trait :inheritance do
      parent_item_consumer

      kind { :inheritance }
      # Inheritance records can't be private.
      item { association(:ai_catalog_flow, :public, organization:) }
    end

    trait :with_triggers do
      transient do
        event_types { [] }
      end

      flow_trigger do
        if parent_item_consumer && event_types.any?
          association(:ai_flow_trigger, :for_catalog_consumer,
            strategy: :build, ai_catalog_item_consumer: instance, project: project, event_types: event_types)
        end
      end
    end
  end
end
