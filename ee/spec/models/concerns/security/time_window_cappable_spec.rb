# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TimeWindowCappable, feature_category: :security_policy_management do
  let(:test_class) do
    Struct.new(:time_window_seconds, :cron_interval, keyword_init: true) do
      include Security::TimeWindowCappable

      def calculate_next_run_at(from_time)
        interval = cron_interval || 1.week.to_i
        next_occurrence = ((from_time.to_i / interval) + 1) * interval
        Time.zone.at(next_occurrence)
      end
    end
  end

  let(:now) { Time.zone.parse('2024-01-01 12:00:00 UTC') }
  let(:cron_interval) { 1.week.to_i }

  subject(:instance) { test_class.new(time_window_seconds: time_window_seconds, cron_interval: cron_interval) }

  describe '#effective_time_window' do
    context 'when time_window_seconds is nil' do
      let(:time_window_seconds) { nil }

      it 'returns nil' do
        travel_to(now) do
          expect(instance.effective_time_window).to be_nil
        end
      end
    end

    context 'when time_window_seconds is less than seconds until next run' do
      let(:time_window_seconds) { 3600 }

      it 'returns the time_window_seconds unchanged' do
        travel_to(now) do
          expect(instance.effective_time_window).to eq(3600)
        end
      end
    end

    context 'when time_window_seconds exceeds seconds until next run' do
      let(:time_window_seconds) { 86_400 }
      let(:cron_interval) { 1.hour.to_i }

      it 'caps to seconds until next run' do
        travel_to(now) do
          next_run_at = instance.calculate_next_run_at(now)
          seconds_until_next = (next_run_at - now).to_i

          expect(instance.effective_time_window).to eq(seconds_until_next)
        end
      end
    end

    context 'when time_window_seconds exactly matches seconds until next run' do
      let(:time_window_seconds) { 3600 }
      let(:cron_interval) { 1.hour.to_i }

      it 'returns the time_window_seconds' do
        travel_to(now) do
          expect(instance.effective_time_window).to eq(3600)
        end
      end
    end

    context 'with a large time_window on a monthly schedule' do
      let(:time_window_seconds) { 30.days.to_i }
      let(:cron_interval) { 1.week.to_i }

      it 'caps to the interval until next run' do
        travel_to(now) do
          next_run_at = instance.calculate_next_run_at(now)
          seconds_until_next = (next_run_at - now).to_i

          expect(instance.effective_time_window).to eq(seconds_until_next)
        end
      end
    end

    context 'when next_run_at is not provided' do
      let(:time_window_seconds) { 3600 }

      it 'falls back to calculate_next_run_at' do
        travel_to(now) do
          expect(instance).to receive(:calculate_next_run_at).with(now).and_call_original

          instance.effective_time_window
        end
      end
    end

    context 'with defer_cap: true' do
      # Scenario: Policy created 2 hours before a weekly cron trigger
      # - Weekly cron fires every 7 days
      # - time_window is 60 hours (should distribute across the weekend)
      # - If created 2 hours before the trigger, without defer_cap the window is capped to 2 hours
      # - With defer_cap: true, it caps against the NEXT week's trigger instead
      let(:cron_interval) { 1.week.to_i }

      context 'when time_window exceeds time until first cron occurrence but not second' do
        let(:time_window_seconds) { 60.hours.to_i }

        it 'uses the full time_window by capping against the second occurrence' do
          first_run = instance.calculate_next_run_at(now)
          two_hours_before_first = first_run - 2.hours

          travel_to(two_hours_before_first) do
            recalculated_first = instance.calculate_next_run_at(two_hours_before_first)
            second_run = instance.calculate_next_run_at(recalculated_first)
            seconds_until_first = (recalculated_first - two_hours_before_first).to_i
            seconds_until_second = (second_run - two_hours_before_first).to_i

            expect(seconds_until_first).to eq(2.hours.to_i)
            expect(seconds_until_second).to eq((1.week + 2.hours).to_i)

            expect(time_window_seconds).to be > seconds_until_first
            expect(time_window_seconds).to be < seconds_until_second

            expect(instance.effective_time_window).to eq(seconds_until_first)

            expect(instance.effective_time_window(nil, defer_cap: true)).to eq(time_window_seconds)
          end
        end
      end

      context 'when time_window exceeds the interval between first and second occurrence' do
        let(:time_window_seconds) { 30.days.to_i }

        it 'caps to the interval between first and second occurrence' do
          first_run = instance.calculate_next_run_at(now)
          two_hours_before_first = first_run - 2.hours

          travel_to(two_hours_before_first) do
            recalculated_first = instance.calculate_next_run_at(two_hours_before_first)
            second_run = instance.calculate_next_run_at(recalculated_first)
            interval_between_occurrences = (second_run - recalculated_first).to_i

            expect(interval_between_occurrences).to eq(1.week.to_i)
            expect(instance.effective_time_window(nil, defer_cap: true)).to eq(interval_between_occurrences)
          end
        end
      end

      context 'when time_window is less than time until first cron occurrence' do
        let(:time_window_seconds) { 1.hour.to_i }

        it 'returns the time_window unchanged' do
          travel_to(now) do
            expect(instance.effective_time_window(nil, defer_cap: true)).to eq(time_window_seconds)
          end
        end
      end
    end

    context 'with defer_cap: false (default)' do
      let(:time_window_seconds) { 60.hours.to_i }
      let(:cron_interval) { 1.week.to_i }

      it 'caps to the first cron occurrence' do
        travel_to(now) do
          first_run = instance.calculate_next_run_at(now)
          seconds_until_first = (first_run - now).to_i

          expect(instance.effective_time_window).to eq(seconds_until_first)
          expect(instance.effective_time_window(nil, defer_cap: false)).to eq(seconds_until_first)
        end
      end
    end

    context 'when reference time is in the past (edge case)' do
      let(:time_window_seconds) { 3600 }

      it 'returns 0 instead of a negative value' do
        travel_to(now) do
          past_time = now - 1.hour

          expect(instance.effective_time_window(past_time)).to eq(0)
        end
      end
    end
  end
end
