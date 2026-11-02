# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::Period, feature_category: :consumables_cost_management do
  describe '.last_completed_day' do
    subject(:last_completed_day) { described_class.last_completed_day }

    around do |example|
      travel_to(Time.utc(2026, 10, 1, 9, 0)) { example.run }
    end

    it 'uses the UTC date rather than the instance time zone, even when local time is already the next day' do
      Time.use_zone('Asia/Tokyo') { expect(last_completed_day).to eq(Date.new(2026, 9, 30)) }
    end

    it 'uses the UTC date rather than the instance time zone, even when local time is still the previous day' do
      Time.use_zone('Pacific/Honolulu') { expect(last_completed_day).to eq(Date.new(2026, 9, 30)) }
    end
  end

  describe '.for_license' do
    subject(:period) { described_class.for_license(license) }

    let(:license) { instance_double(Gitlab::License, starts_at: starts_at, expires_at: expires_at) }
    let(:starts_at) { Date.new(2026, 8, 1) }

    around do |example|
      travel_to(Time.utc(2026, 10, 1, 9, 0)) { example.run }
    end

    context 'when the term is still running' do
      let(:expires_at) { Date.new(2027, 8, 1) }

      it 'runs from the license start to the last completed day', :aggregate_failures do
        expect(period.start_date).to eq(Date.new(2026, 8, 1))
        expect(period.end_date).to eq(Date.new(2026, 9, 30))
      end
    end

    context 'when the term has ended' do
      let(:starts_at) { Date.new(2025, 8, 1) }
      let(:expires_at) { Date.new(2026, 8, 1) }

      it 'ends on the day before the license expires', :aggregate_failures do
        expect(period.start_date).to eq(Date.new(2025, 8, 1))
        expect(period.end_date).to eq(Date.new(2026, 7, 31))
      end
    end

    context 'when the license does not expire' do
      let(:expires_at) { nil }

      it 'ends on the last completed day' do
        expect(period.end_date).to eq(Date.new(2026, 9, 30))
      end
    end
  end

  describe '#empty?' do
    it 'is true when start_date is after end_date' do
      period = described_class.new(start_date: Date.new(2026, 8, 5), end_date: Date.new(2026, 8, 1))

      expect(period).to be_empty
    end

    it 'is false for a single-day period' do
      period = described_class.new(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 1))

      expect(period).not_to be_empty
    end

    it 'is false for a normal range' do
      period = described_class.new(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 5))

      expect(period).not_to be_empty
    end
  end

  describe '#range' do
    it 'returns start_date..end_date' do
      period = described_class.new(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 5))

      expect(period.range).to eq(Date.new(2026, 8, 1)..Date.new(2026, 8, 5))
    end
  end
end
