# frozen_string_literal: true

FactoryBot.define do
  factory :billable_usage_export_log, class: 'Utilization::BillableUsage::ExportLog' do
    period_start { Date.new(2026, 8, 1) }
    period_end { Date.new(2026, 8, 31) }
    generated_at { Time.current }
    association :generated_by, factory: :user
    record_count { 3 }
    payload_checksum { SecureRandom.hex(32) }
  end
end
