# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::RelativeDate, feature_category: :team_planning do
  using RSpec::Parameterized::TableSyntax

  describe '.to_date' do
    context 'when today is the last day of a 31-day month' do
      around do |example|
        travel_to(Time.zone.parse('2026-03-31 15:00:00')) { example.run }
      end

      where(:amount, :unit, :expected) do
        0    | 'DAY'   | Date.new(2026, 3, 31)
        -7   | 'DAY'   | Date.new(2026, 3, 24)
        7    | 'DAY'   | Date.new(2026, 4, 7)
        -2   | 'WEEK'  | Date.new(2026, 3, 17)
        2    | 'WEEK'  | Date.new(2026, 4, 14)
        -1   | 'MONTH' | Date.new(2026, 2, 28)
        1    | 'MONTH' | Date.new(2026, 4, 30)
        -1   | 'YEAR'  | Date.new(2025, 3, 31)
        9999 | 'DAY'   | Date.new(2053, 8, 15)
      end

      with_them do
        it 'returns the date relative to today' do
          expect(described_class.to_date(amount: amount, unit: unit)).to eq(expected)
        end
      end

      it 'accepts the unit as a symbol' do
        expect(described_class.to_date(amount: -1, unit: :WEEK)).to eq(Date.new(2026, 3, 24))
      end

      it 'raises KeyError for an unknown unit' do
        expect { described_class.to_date(amount: 1, unit: 'HOUR') }.to raise_error(KeyError)
      end

      context 'when the date is out of range' do
        where(:amount) { [9999, -9999] }

        with_them do
          it 'raises OutOfRangeError' do
            expect { described_class.to_date(amount: amount, unit: 'YEAR') }
              .to raise_error(described_class::OutOfRangeError, "Relative date #{amount} YEAR is out of range")
          end
        end
      end
    end

    context 'when today is a leap day' do
      around do |example|
        travel_to(Time.zone.parse('2028-02-29 12:00:00')) { example.run }
      end

      it 'clamps to the last day of the month' do
        expect(described_class.to_date(amount: -1, unit: 'YEAR')).to eq(Date.new(2027, 2, 28))
      end
    end

    context 'when it is already the next day in the given time zone' do
      around do |example|
        travel_to(Time.utc(2026, 3, 31, 20, 0, 0)) { example.run }
      end

      it 'uses the date in that time zone' do
        zone = ActiveSupport::TimeZone['Pacific/Auckland']

        expect(described_class.to_date(amount: 0, unit: 'DAY', zone: zone)).to eq(Date.new(2026, 4, 1))
      end
    end
  end
end
