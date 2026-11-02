# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::Coverage, feature_category: :consumables_cost_management do
  describe '#to_h' do
    subject(:result) do
      described_class.new(seat_link_series: seat_link_series, billable_events_dates: billable_events_dates).to_h
    end

    let(:seat_link_series) do
      Utilization::BillableUsage::Exports::SeatLinkSeries.new(period_start: period_start, period_end: period_end)
    end

    let(:billable_events_dates) { [] }

    context 'with a 5-day period where seat link has full coverage and billable events has gaps' do
      let(:period_start) { Date.new(2026, 8, 1) }
      let(:period_end) { Date.new(2026, 8, 5) }
      let(:billable_events_dates) { [Date.new(2026, 8, 1), Date.new(2026, 8, 3), Date.new(2026, 8, 5)] }

      before do
        (1..5).each do |day|
          create(:historical_data, recorded_at: Time.utc(2026, 8, day, 12, 0), active_user_count: day * 10)
        end
      end

      it 'reports full seat link coverage and only a day count for billable_events' do
        expect(result).to eq(
          {
            period_days: 5,
            seat_link: {
              included: true,
              expected_days: 5,
              days_with_data: 5,
              complete: true,
              no_data_dates: []
            },
            billable_events: { included: true, days_with_data: 3 }
          })
      end
    end

    context 'with a single-day period' do
      let(:period_start) { Date.new(2026, 8, 10) }
      let(:period_end) { Date.new(2026, 8, 10) }

      before do
        create(:historical_data, recorded_at: Time.utc(2026, 8, 10, 12, 0), active_user_count: 7)
      end

      it 'treats both ends of the range as the same inclusive day' do
        expect(result).to eq(
          {
            period_days: 1,
            seat_link: {
              included: true,
              expected_days: 1,
              days_with_data: 1,
              complete: true,
              no_data_dates: []
            },
            billable_events: { included: true, days_with_data: 0 }
          })
      end
    end

    context 'with no data at all in the period' do
      let(:period_start) { Date.new(2026, 8, 1) }
      let(:period_end) { Date.new(2026, 8, 3) }

      it 'marks seat link incomplete with every day missing, and counts no billable_events days' do
        expect(result).to eq(
          {
            period_days: 3,
            seat_link: {
              included: true,
              expected_days: 3,
              days_with_data: 0,
              complete: false,
              no_data_dates: %w[2026-08-01 2026-08-02 2026-08-03]
            },
            billable_events: { included: true, days_with_data: 0 }
          })
      end
    end

    context 'when period_start is after period_end' do
      let(:period_start) { Date.new(2026, 8, 5) }
      let(:period_end) { Date.new(2026, 8, 1) }

      it 'returns empty coverage for both datasets without querying seat link data', :aggregate_failures do
        expect(HistoricalData).not_to receive(:daily_maximums_on_utc_dates)

        expect(result).to eq(
          {
            period_days: 0,
            seat_link: {
              included: true,
              expected_days: 0,
              days_with_data: 0,
              complete: true,
              no_data_dates: []
            },
            billable_events: { included: true, days_with_data: 0 }
          })
      end
    end

    context 'when billable events dates repeat or fall outside the period' do
      let(:period_start) { Date.new(2026, 8, 1) }
      let(:period_end) { Date.new(2026, 8, 3) }
      let(:billable_events_dates) do
        [Date.new(2026, 7, 31), Date.new(2026, 8, 1), Date.new(2026, 8, 1), Date.new(2026, 8, 3), Date.new(2026, 8, 4)]
      end

      it 'counts each day in the period once' do
        expect(result[:billable_events]).to eq({ included: true, days_with_data: 2 })
      end
    end

    context 'when the series already holds its dates' do
      let(:seat_link_series) do
        instance_double(Utilization::BillableUsage::Exports::SeatLinkSeries,
          period_start: Date.new(2026, 8, 1),
          period_end: Date.new(2026, 8, 2),
          dates: [Date.new(2026, 8, 1), Date.new(2026, 8, 2)])
      end

      it 'takes the period and dates from the series without querying HistoricalData', :aggregate_failures do
        expect(HistoricalData).not_to receive(:daily_maximums_on_utc_dates)

        expect(result[:period_days]).to eq(2)
        expect(result[:seat_link]).to eq(
          {
            included: true,
            expected_days: 2,
            days_with_data: 2,
            complete: true,
            no_data_dates: []
          })
      end
    end

    context 'when Time.zone is not UTC' do
      let(:period_start) { Date.new(2026, 8, 31) }
      let(:period_end) { Date.new(2026, 8, 31) }

      it 'does not report a phantom no_data_date for a row recorded at 23:30 UTC on the last day' do
        Time.use_zone('Asia/Tokyo') do
          create(:historical_data, recorded_at: Time.utc(2026, 8, 31, 23, 30), active_user_count: 4)

          expect(result[:seat_link]).to eq(
            {
              included: true,
              expected_days: 1,
              days_with_data: 1,
              complete: true,
              no_data_dates: []
            })
        end
      end
    end
  end
end
