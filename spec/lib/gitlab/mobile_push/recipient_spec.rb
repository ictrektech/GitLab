# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MobilePush::Recipient, feature_category: :notifications do
  let(:user) { create(:user) }

  subject(:recipient) { described_class.new(user) }

  describe '#skip_reason' do
    it 'is nil for an active user with a phone' do
      create(:mobile_device_push_subscription, user: user)

      expect(recipient.skip_reason).to be_nil
    end

    it 'names a missing or inactive user' do
      expect(described_class.new(nil).skip_reason).to eq(:skipped_user_inactive)

      user.block!

      expect(recipient.skip_reason).to eq(:skipped_user_inactive)
    end

    it 'names missing phones' do
      expect(recipient.skip_reason).to eq(:skipped_no_subscription)
    end
  end

  describe '#subscriptions' do
    it 'loads the phones once' do
      create_list(:mobile_device_push_subscription, 2, user: user)

      expect(recipient.subscriptions.size).to eq(2)
      expect { recipient.subscriptions }.not_to exceed_query_limit(0)
    end
  end

  describe 'the schedule' do
    it 'answers from the user preference' do
      user.user_preference.update!(
        mobile_push_working_hours_enabled: true,
        mobile_push_working_hours_start: 9 * 60,
        mobile_push_working_hours_end: 17 * 60,
        mobile_push_working_days: %w[monday tuesday wednesday thursday friday],
        mobile_push_working_hours_time_zone: 'Europe/Berlin'
      )

      travel_to(Time.utc(2026, 10, 6, 22, 0)) do # Wednesday 00:00 in Berlin
        expect(recipient.working_hours_enabled?).to be(true)
        expect(recipient.deliver_now?).to be(false)
        expect(recipient.next_window_start).to eq(Time.utc(2026, 10, 7, 7, 0))
      end
    end

    it 'evaluates the time it is given' do
      user.user_preference.update!(
        mobile_push_working_hours_enabled: true,
        mobile_push_working_hours_start: 9 * 60,
        mobile_push_working_hours_end: 17 * 60,
        mobile_push_working_days: %w[monday tuesday wednesday thursday friday],
        mobile_push_working_hours_time_zone: 'Europe/Berlin'
      )
      inside = Time.utc(2026, 10, 6, 8, 0) # Tuesday 10:00 in Berlin

      expect(recipient.deliver_now?(inside)).to be(true)
      expect(recipient.next_window_start(inside)).to eq(Time.utc(2026, 10, 7, 7, 0))
    end
  end
end
