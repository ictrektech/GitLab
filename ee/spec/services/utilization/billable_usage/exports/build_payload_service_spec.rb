# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::BuildPayloadService, feature_category: :consumables_cost_management do
  describe '#execute' do
    let(:license) { build(:license) }
    let(:generated_at) { Time.utc(2026, 8, 13, 8, 0) }

    subject(:result) { described_class.new(period: period, license: license, generated_at: generated_at).execute }

    def build_period(start_date:, end_date:)
      Utilization::BillableUsage::Exports::Period.new(start_date: start_date, end_date: end_date)
    end

    context 'with usage in the period' do
      let(:period) { build_period(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 12)) }

      before do
        create(:historical_data, recorded_at: Time.utc(2026, 8, 10, 12, 0), active_user_count: 5)
        create(:historical_data, recorded_at: Time.utc(2026, 8, 11, 12, 0), active_user_count: 7)

        create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 10), quantity: 30, events_count: 5)
        create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 11), quantity: 5, events_count: 1)

        # Outside the period: must not be counted.
        create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 20))
      end

      it 'succeeds' do
        expect(result).to be_success
      end

      it 'exports one record per day per usage type', :aggregate_failures do
        document = result.payload[:document]

        expect(document['record_count']).to eq(2)
        expect(document['records'].size).to eq(2)
      end

      it 'keeps seat link coverage and seat link records in agreement' do
        document = result.payload[:document]

        expect(document['coverage']['seat_link']['days_with_data']).to eq(document['seat_link']['records'].size)
      end

      it 'counts billable events coverage from the exported records' do
        expect(result.payload[:document]['coverage']['billable_events']['days_with_data']).to eq(2)
      end

      it 'includes the instance identity fields', :aggregate_failures do
        document = result.payload[:document]
        identity = Gitlab::BillingEvents::InstanceIdentity.to_h

        identity.each do |key, value|
          expect(document[key.to_s]).to eq(value)
        end
      end

      it 'includes the license key' do
        document = result.payload[:document]

        expect(document['license_key']).to eq(license.normalized_data)
      end

      it 'encodes the period and generation time as ISO 8601 strings', :aggregate_failures do
        document = result.payload[:document]

        expect(document['period_start']).to eq('2026-08-10')
        expect(document['period_end']).to eq('2026-08-12')
        expect(document['generated_at']).to eq('2026-08-13T08:00:00Z')
      end

      it 'seals the document with a checksum a verifier can recompute after stripping it' do
        document = result.payload[:document]

        expect(Utilization::BillableUsage::Exports::Checksum.digest(document)).to eq(document['checksum'])
      end

      it 'serializes to JSON that parses back into the same document' do
        parsed_json = Gitlab::Json::SafeParser.parse(result.payload[:json])

        expect(parsed_json).to eq(result.payload[:document])
      end
    end

    context 'with an empty period' do
      let(:period) { build_period(start_date: Date.new(2026, 8, 12), end_date: Date.new(2026, 8, 10)) }

      it 'succeeds with an empty document, without querying either dataset', :aggregate_failures do
        expect(Utilization::BillableUsage::Exports::UsageRecordsService).not_to receive(:new)
        expect(HistoricalData).not_to receive(:daily_maximums_on_utc_dates)

        document = result.payload[:document]

        expect(result).to be_success
        expect(document['record_count']).to eq(0)
        expect(document['records']).to eq([])
        expect(document['coverage']['period_days']).to eq(0)
      end
    end

    context 'when a summed quantity exceeds the export ceiling' do
      let(:period) { build_period(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 10)) }

      before do
        max_quantity = Utilization::BillableUsage::DailyNamespaceAggregate::MAX_QUANTITY

        create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 10), quantity: max_quantity * 2)
      end

      it 'returns an error naming the day', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:quantity_exceeds_ceiling)
        expect(result.message).to include('2026-08-10')
      end
    end

    context 'without a license' do
      let(:license) { nil }
      let(:period) { build_period(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 10)) }

      it 'returns an error rather than raising', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:license_missing)
      end
    end

    context 'when the rendered JSON exceeds the file size limit' do
      let(:period) { build_period(start_date: Date.new(2026, 8, 10), end_date: Date.new(2026, 8, 10)) }

      before do
        stub_const("#{described_class}::FILESIZE_LIMIT", 10)

        create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 10))
      end

      it 'returns an error without truncating the file', :aggregate_failures do
        expect(result).to be_error
        expect(result.reason).to eq(:file_too_large)
      end
    end
  end
end
