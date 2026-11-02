# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::ExportLog, feature_category: :consumables_cost_management do
  describe 'factory' do
    it 'produces a valid record' do
      expect(build(:billable_usage_export_log)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:generated_by).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:period_start) }
    it { is_expected.to validate_presence_of(:period_end) }
    it { is_expected.to validate_presence_of(:generated_at) }
    it { is_expected.to validate_presence_of(:payload_checksum) }

    it 'is valid with only the minimum required attributes' do
      export = described_class.new(
        period_start: Date.new(2026, 8, 1),
        period_end: Date.new(2026, 8, 31),
        generated_at: Time.current,
        payload_checksum: SecureRandom.hex(32)
      )

      expect(export).to be_valid
    end

    describe 'payload_checksum' do
      it 'accepts 64 lowercase hex characters' do
        expect(build(:billable_usage_export_log, payload_checksum: 'a' * 64)).to be_valid
      end

      it 'rejects 63 characters' do
        record = build(:billable_usage_export_log, payload_checksum: 'a' * 63)

        expect(record).to be_invalid
        expect(record.errors[:payload_checksum]).to be_present
      end

      it 'rejects 65 characters' do
        record = build(:billable_usage_export_log, payload_checksum: 'a' * 65)

        expect(record).to be_invalid
        expect(record.errors[:payload_checksum]).to be_present
      end

      it 'rejects uppercase hex, so the digest has one canonical form' do
        record = build(:billable_usage_export_log, payload_checksum: 'A' * 64)

        expect(record).to be_invalid
        expect(record.errors[:payload_checksum]).to be_present
      end

      it 'rejects non-hex characters' do
        record = build(:billable_usage_export_log, payload_checksum: "#{'a' * 63}z")

        expect(record).to be_invalid
        expect(record.errors[:payload_checksum]).to be_present
      end
    end

    describe 'record_count' do
      it 'is valid at zero, since a period with no usage is a legitimate export' do
        expect(build(:billable_usage_export_log, record_count: 0)).to be_valid
      end

      it 'is invalid below zero' do
        record = build(:billable_usage_export_log, record_count: -1)

        expect(record).to be_invalid
        expect(record.errors[:record_count]).to be_present
      end

      it 'is invalid when not a whole number' do
        record = build(:billable_usage_export_log, record_count: 1.5)

        expect(record).to be_invalid
        expect(record.errors[:record_count]).to be_present
      end
    end

    describe 'period ordering' do
      let(:period_start) { Date.new(2026, 8, 1) }

      it 'accepts a single-day period' do
        record = build(:billable_usage_export_log, period_start: period_start, period_end: period_start)

        expect(record).to be_valid
      end

      it 'rejects a period ending the day before it starts' do
        record = build(:billable_usage_export_log, period_start: period_start, period_end: period_start - 1.day)

        expect(record).to be_invalid
        expect(record.errors[:period_end]).to be_present
      end
    end
  end

  describe '.last_generated_at_for' do
    let(:period_start) { Date.new(2026, 8, 1) }

    subject(:last_generated_at) { described_class.last_generated_at_for(period_start: period_start) }

    it 'returns nil when the period has never been exported' do
      expect(last_generated_at).to be_nil
    end

    it 'returns the latest generated_at for the period, ignoring other periods' do
      create(:billable_usage_export_log, period_start: period_start, generated_at: Time.utc(2026, 8, 10, 9, 0))
      create(:billable_usage_export_log, period_start: period_start, generated_at: Time.utc(2026, 8, 20, 9, 0))
      create(:billable_usage_export_log, period_start: Date.new(2025, 8, 1), period_end: Date.new(2026, 7, 31),
        generated_at: Time.utc(2026, 9, 1, 9, 0))

      expect(last_generated_at).to eq(Time.utc(2026, 8, 20, 9, 0))
    end
  end

  describe 'database constraints' do
    let(:export) { create(:billable_usage_export_log) }

    it 'rejects a period ending before it starts' do
      expect { export.update_column(:period_end, export.period_start - 1.day) }
        .to raise_error(ActiveRecord::StatementInvalid, /check_billable_usage_export_logs_period_end_after_start/)
    end

    it 'rejects a negative record_count' do
      expect { export.update_column(:record_count, -1) }
        .to raise_error(ActiveRecord::StatementInvalid,
          /check_billable_usage_export_logs_record_count_non_negative/)
    end

    it 'rejects an uppercase payload_checksum' do
      expect { export.update_column(:payload_checksum, 'A' * 64) }
        .to raise_error(ActiveRecord::StatementInvalid, /check_billable_usage_export_logs_payload_checksum_format/)
    end

    it 'rejects a non-hex payload_checksum' do
      expect { export.update_column(:payload_checksum, 'z' * 64) }
        .to raise_error(ActiveRecord::StatementInvalid, /check_billable_usage_export_logs_payload_checksum_format/)
    end

    it 'permits two exports covering the same period, since a period may be re-generated' do
      attrs = { period_start: export.period_start, period_end: export.period_end }

      expect { create(:billable_usage_export_log, **attrs) }.to change { described_class.count }.by(1)
    end
  end

  context 'with a loose foreign key on users' do
    it_behaves_like 'cleanup by a loose foreign key', on_delete: :async_nullify do
      let!(:parent) { create(:user) }
      let!(:model) { create(:billable_usage_export_log, generated_by: parent) }
    end
  end
end
