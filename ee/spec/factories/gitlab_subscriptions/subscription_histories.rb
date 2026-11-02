# frozen_string_literal: true

FactoryBot.define do
  factory :gitlab_subscription_history, class: 'GitlabSubscriptions::SubscriptionHistory' do
    transient do
      # Takes a Plan record or a GitlabSubscriptions::SystemDefined::Plan
      hosted_plan { nil }
    end

    association :namespace, factory: :group_with_plan, plan: :premium_plan
    hosted_plan_name_uid { hosted_plan&.plan_name_uid_before_type_cast }

    after(:build) do |history|
      gitlab_subscription = history.namespace.gitlab_subscription
      history.gitlab_subscription_id = SecureRandom.random_number(100_000)

      history.gitlab_subscription_id = gitlab_subscription.id if history.namespace.gitlab_subscription.present?
    end

    trait :update do
      change_type { :gitlab_subscription_updated }
    end

    trait :destroyed do
      change_type { :gitlab_subscription_destroyed }
    end
  end
end
