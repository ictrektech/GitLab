# frozen_string_literal: true

FactoryBot.define do
  factory :govern_policy, class: 'Govern::Policy' do
    namespace { association(:group) }
    organization { namespace.organization }
    sequence(:name) { |n| "govern-policy-#{n}" }
    trigger_type { :'project.before_settings_update' }

    trait :without_namespace do
      namespace { nil }
      organization { association(:organization) }
    end
  end
end
