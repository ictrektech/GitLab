# frozen_string_literal: true

FactoryBot.define do
  factory :billable_usage_daily_total, class: 'Utilization::BillableUsage::DailyTotal' do
    usage_date { Date.current }
    event_type { 'secrets_read' }
    unit_of_measure { 'request' }
    feature_qualified_name { 'secrets_read' }
    quantity { 1 }
    events_count { 1 }
    source_updated_at { Time.current }
  end
end
