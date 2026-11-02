# frozen_string_literal: true

FactoryBot.define do
  factory :gitlab_subscription do
    after(:build) do
      raise 'not under .com or SaaS feature not stubbed' unless Gitlab.com? || StubSaasFeatures.features_stubbed
    end

    transient do
      # Takes a Plan record or a GitlabSubscriptions::SystemDefined::Plan
      hosted_plan { association(:ultimate_plan) }
    end

    namespace
    hosted_plan_name_uid { hosted_plan&.plan_name_uid_before_type_cast }
    seats { 10 }
    start_date { Date.current }
    end_date { Date.current.advance(years: 1) }
    trial { false }
    contract_overages_allowed { true }

    trait :with_group do
      association :namespace, factory: :group
    end

    trait :expired do
      start_date { Date.current.advance(years: -1, months: -1) }
      end_date { Date.current.advance(months: -1) }
    end

    trait :active_trial do
      trial { true }
      trial_starts_on { Date.current.advance(days: -15) }
      trial_ends_on { Date.current.advance(days: 15) }
    end

    trait :expired_trial do
      trial { true }
      trial_starts_on { Date.current.advance(days: -31) }
      trial_ends_on { Date.current.advance(days: -1) }
    end

    trait :default do
      transient { hosted_plan { association(:default_plan) } }
    end

    trait :free do
      transient { hosted_plan { nil } }
    end

    trait :bronze do
      transient { hosted_plan { association(:bronze_plan) } }
    end

    trait :silver do
      transient { hosted_plan { association(:silver_plan) } }
    end

    trait :premium do
      transient { hosted_plan { association(:premium_plan) } }
    end

    trait :gold do
      transient { hosted_plan { association(:gold_plan) } }
    end

    trait :ultimate do
      transient { hosted_plan { association(:ultimate_plan) } }
    end

    trait :premium_trial do
      transient { hosted_plan { association(:premium_trial_plan) } }
    end

    trait :ultimate_trial do
      transient { hosted_plan { association(:ultimate_trial_plan) } }
    end

    trait :ultimate_trial_paid_customer do
      transient { hosted_plan { association(:ultimate_trial_paid_customer_plan) } }
    end

    trait :opensource do
      transient { hosted_plan { association(:opensource_plan) } }
    end
  end
end
