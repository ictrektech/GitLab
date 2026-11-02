# frozen_string_literal: true

FactoryBot.define do
  factory :gitlab_subscription_trial_usage, class: 'GitlabSubscriptions::TrialUsage' do
    namespace { association(:group) }
    trial_starts_on { 30.days.ago.to_date }
    trial_ends_on { Date.current }
    compute_minutes_month { Date.current.beginning_of_month }
  end
end
