# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::DailyTotal, feature_category: :consumables_cost_management do
  it 'has a valid factory' do
    expect(build(:billable_usage_daily_total)).to be_valid
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:source_updated_at) }
    it { is_expected.to validate_presence_of(:usage_date) }
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:unit_of_measure) }
    it { is_expected.to validate_presence_of(:feature_qualified_name) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_presence_of(:events_count) }
    it { is_expected.to validate_presence_of(:schema_version) }

    it { is_expected.to validate_length_of(:event_type).is_at_most(255) }
    it { is_expected.to validate_length_of(:feature_qualified_name).is_at_most(255) }
    it { is_expected.to validate_length_of(:unit_of_measure).is_at_most(64) }
    it { is_expected.to validate_length_of(:operation_type).is_at_most(64) }

    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:events_count).is_greater_than_or_equal_to(0).only_integer }

    it 'allows a nil operation_type' do
      expect(build(:billable_usage_daily_total, operation_type: nil)).to be_valid
    end

    it 'allows a quantity above the per-namespace ceiling' do
      quantity = Utilization::BillableUsage::DailyNamespaceAggregate::MAX_QUANTITY + 1

      expect(build(:billable_usage_daily_total, quantity: quantity)).to be_valid
    end
  end

  describe 'database uniqueness' do
    it 'raises when the tuple is duplicated and operation_type is null on both' do
      create(:billable_usage_daily_total, operation_type: nil)

      expect { create(:billable_usage_daily_total, operation_type: nil) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permits a second record when only operation_type differs' do
      create(:billable_usage_daily_total, operation_type: 'regular')

      expect { create(:billable_usage_daily_total, operation_type: 'compaction_auto') }
        .to change { described_class.count }.by(1)
    end
  end

  describe '.watermark' do
    it 'is nil without totals' do
      expect(described_class.watermark).to be_nil
    end

    it 'is the latest source_updated_at' do
      latest = 1.hour.ago.change(usec: 0)
      create(:billable_usage_daily_total, usage_date: Date.current, source_updated_at: 2.hours.ago)
      create(:billable_usage_daily_total, usage_date: Date.yesterday, source_updated_at: latest)

      expect(described_class.watermark).to eq(latest)
    end
  end

  describe 'export scopes' do
    let(:usage_date) { Date.new(2026, 8, 10) }

    describe '.in_period' do
      it 'is inclusive of both ends' do
        create(:billable_usage_daily_total, usage_date: usage_date)
        create(:billable_usage_daily_total, usage_date: usage_date + 2.days)

        expect(described_class.in_period(usage_date..(usage_date + 2.days)).count).to eq(2)
        expect(described_class.in_period(usage_date..(usage_date + 1.day)).count).to eq(1)
      end
    end

    describe '.ordered_for_export' do
      it 'orders by day, so the record sequence a checksum covers is stable' do
        create(:billable_usage_daily_total, usage_date: usage_date + 1.day)
        create(:billable_usage_daily_total, usage_date: usage_date)

        expect(described_class.ordered_for_export.map(&:usage_date)).to eq([usage_date, usage_date + 1.day])
      end

      it 'puts a null operation_type first, rather than leaving it to a default' do
        create(:billable_usage_daily_total, usage_date: usage_date, operation_type: 'regular')
        create(:billable_usage_daily_total, usage_date: usage_date, operation_type: nil)

        expect(described_class.ordered_for_export.map(&:operation_type)).to eq([nil, 'regular'])
      end
    end
  end
end
