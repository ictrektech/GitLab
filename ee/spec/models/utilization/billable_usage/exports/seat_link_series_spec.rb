# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::SeatLinkSeries, feature_category: :consumables_cost_management do
  describe '#records' do
    subject(:records) { described_class.new(period_start: period_start, period_end: period_end).records }

    let(:period_start) { Date.new(2026, 8, 1) }
    let(:period_end) { Date.new(2026, 8, 3) }

    it 'returns one record per day as an ISO 8601 date string and an integer count, ascending' do
      create(:historical_data, recorded_at: Time.utc(2026, 8, 3, 12, 0), active_user_count: 30)
      create(:historical_data, recorded_at: Time.utc(2026, 8, 1, 12, 0), active_user_count: 10)

      expect(records).to eq(
        [
          { date: '2026-08-01', billable_user_count: 10 },
          { date: '2026-08-03', billable_user_count: 30 }
        ])
    end

    context 'when period_start is after period_end' do
      let(:period_start) { Date.new(2026, 8, 3) }
      let(:period_end) { Date.new(2026, 8, 1) }

      it 'returns an empty array without querying', :aggregate_failures do
        expect(HistoricalData).not_to receive(:daily_maximums_on_utc_dates)

        expect(records).to eq([])
      end
    end
  end

  describe '#dates' do
    subject(:dates) { described_class.new(period_start: period_start, period_end: period_end).dates }

    let(:period_start) { Date.new(2026, 8, 1) }
    let(:period_end) { Date.new(2026, 8, 2) }

    it 'returns the Dates present in the period, ascending' do
      create(:historical_data, recorded_at: Time.utc(2026, 8, 2, 12, 0), active_user_count: 5)
      create(:historical_data, recorded_at: Time.utc(2026, 8, 1, 12, 0), active_user_count: 5)

      expect(dates).to eq([Date.new(2026, 8, 1), Date.new(2026, 8, 2)])
    end

    context 'when period_start is after period_end' do
      let(:period_start) { Date.new(2026, 8, 3) }
      let(:period_end) { Date.new(2026, 8, 1) }

      it 'returns an empty array' do
        expect(dates).to eq([])
      end
    end
  end
end
