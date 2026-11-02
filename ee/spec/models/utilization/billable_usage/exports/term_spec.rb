# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::Term, feature_category: :consumables_cost_management do
  def create_license(*traits, starts_at:, expires_at:, **license_options)
    data = build(:gitlab_license, *traits, starts_at: starts_at, expires_at: expires_at).export

    build(:license, data: data, **license_options).tap { |license| license.save!(validate: false) }
  end

  around do |example|
    travel_to(Time.utc(2026, 10, 1, 9, 0)) { example.run }
  end

  let_it_be(:oldest_license) { create_license(starts_at: Date.new(2024, 8, 1), expires_at: Date.new(2025, 8, 1)) }
  let_it_be(:previous_license) { create_license(starts_at: Date.new(2025, 8, 1), expires_at: Date.new(2026, 8, 1)) }
  let_it_be(:current_license) { create_license(starts_at: Date.new(2026, 8, 1), expires_at: Date.new(2027, 8, 1)) }

  before do
    allow(License).to receive(:current).and_return(current_license)
  end

  describe '.available' do
    subject(:available) { described_class.available }

    it 'returns the current and the previous term, newest first' do
      expect(available.map(&:license)).to eq([current_license, previous_license])
    end

    context 'with a future-dated license' do
      before do
        create_license(starts_at: Date.new(2027, 8, 1), expires_at: Date.new(2028, 8, 1))
      end

      it 'leaves it out' do
        expect(available.map(&:license)).to eq([current_license, previous_license])
      end
    end

    context 'with a trial license' do
      before do
        create_license(:trial, starts_at: Date.new(2026, 9, 1), expires_at: Date.new(2026, 10, 1))
      end

      it 'leaves it out' do
        expect(available.map(&:license)).to eq([current_license, previous_license])
      end
    end

    context 'with a reissued license for the current term' do
      let!(:reissued_license) do
        create_license(starts_at: Date.new(2026, 8, 1), expires_at: Date.new(2027, 8, 1),
          created_at: current_license.created_at + 1.day)
      end

      it 'keeps only the newest license for that term' do
        expect(available.map(&:license)).to eq([reissued_license, previous_license])
      end
    end
  end

  describe '.find' do
    it 'returns the available term for the license id' do
      expect(described_class.find(previous_license.id.to_s).license).to eq(previous_license)
    end

    it 'returns nil for a license older than the available terms' do
      expect(described_class.find(oldest_license.id)).to be_nil
    end

    it 'returns nil for an unknown license id' do
      expect(described_class.find(non_existing_record_id)).to be_nil
    end
  end

  describe '.current' do
    it 'returns the term of the current license' do
      expect(described_class.current.license).to eq(current_license)
    end
  end

  describe '#current?' do
    it 'is true only for the term of the current license', :aggregate_failures do
      expect(described_class.new(current_license).current?).to be(true)
      expect(described_class.new(previous_license).current?).to be(false)
    end

    context 'without a current license' do
      before do
        allow(License).to receive(:current).and_return(nil)
      end

      it 'is false' do
        expect(described_class.new(current_license).current?).to be(false)
      end
    end
  end

  describe '#end_date' do
    it 'is the day before the license expires' do
      expect(described_class.new(previous_license).end_date).to eq(Date.new(2026, 7, 31))
    end

    it 'is nil for a license that never expires' do
      license = build(:license, starts_at: Date.new(2026, 8, 1), expires_at: nil)

      expect(described_class.new(license).end_date).to be_nil
    end
  end

  describe '#period' do
    it 'covers the whole of a past term', :aggregate_failures do
      period = described_class.new(previous_license).period

      expect(period.start_date).to eq(Date.new(2025, 8, 1))
      expect(period.end_date).to eq(Date.new(2026, 7, 31))
    end
  end

  describe '#last_exported_at' do
    subject(:last_exported_at) { described_class.new(previous_license).last_exported_at }

    it 'is nil when the term was never exported' do
      expect(last_exported_at).to be_nil
    end

    context 'when the term was exported' do
      before do
        create(:billable_usage_export_log, period_start: Date.new(2025, 8, 1), period_end: Date.new(2026, 7, 31),
          generated_at: Time.utc(2026, 8, 2, 9, 12))
        create(:billable_usage_export_log, period_start: Date.new(2025, 8, 1), period_end: Date.new(2026, 7, 31),
          generated_at: Time.utc(2026, 8, 3, 9, 12))
        create(:billable_usage_export_log, period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 9, 30),
          generated_at: Time.utc(2026, 10, 1, 8, 0))
      end

      it 'is the latest export of that term' do
        expect(last_exported_at).to eq(Time.utc(2026, 8, 3, 9, 12))
      end
    end
  end
end
