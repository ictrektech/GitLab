# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::UsageRecordsService,
  feature_category: :consumables_cost_management do
  let(:usage_date) { Date.new(2026, 8, 10) }
  let(:period) { usage_date..(usage_date + 5.days) }

  subject(:records) { described_class.new(period).execute }

  context 'with daily totals in the period' do
    before do
      create(:billable_usage_daily_total,
        usage_date: usage_date, event_type: 'secrets_read', feature_qualified_name: 'secrets_read',
        quantity: 30, events_count: 9)
      create(:billable_usage_daily_total,
        usage_date: usage_date + 1.day, event_type: 'secrets_stored', feature_qualified_name: 'secrets_stored',
        unit_of_measure: 'secret', quantity: 1162, events_count: 2)
    end

    it 'returns one record per day per usage type' do
      expect(records.size).to eq(2)
    end

    it 'carries each total as it is stored', :aggregate_failures do
      read = records.find { |r| r[:event_type] == 'secrets_read' }

      expect(read[:quantity]).to eq(30.0)
      expect(read[:metadata][:events_count]).to eq(9)
    end

    it 'orders records by day, so the checksum over them is stable' do
      expect(records.map { |r| r[:timestamp] })
        .to eq(['2026-08-10T12:00:00Z', '2026-08-11T12:00:00Z'])
    end

    it 'excludes days outside the period' do
      create(:billable_usage_daily_total, usage_date: usage_date + 30.days)

      expect(records.size).to eq(2)
    end
  end

  context 'when the totals were refreshed from per-namespace usage' do
    before do
      [1, 2, nil].each do |namespace_id|
        create(:billable_usage_daily_namespace_aggregate,
          usage_date: usage_date, event_type: 'secrets_read', feature_qualified_name: 'secrets_read',
          quantity: 10, events_count: 3, root_namespace_id: namespace_id)
      end

      Utilization::BillableUsage::RefreshDailyTotalsService.new.execute
    end

    it 'exports one record summed across namespaces', :aggregate_failures do
      expect(records.size).to eq(1)
      expect(records.first[:quantity]).to eq(30.0)
      expect(records.first[:metadata][:events_count]).to eq(9)
    end
  end

  context 'with no usage in the period' do
    it 'returns no records, since a period with nothing recorded is still exportable' do
      expect(records).to eq([])
    end
  end
end
