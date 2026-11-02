# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MobilePush::HeldSummary, :clean_gitlab_redis_shared_state, feature_category: :notifications do
  let_it_be(:project) { create(:project) }

  let(:user) { create(:user) }
  let(:client) { instance_double(::Gitlab::MobilePush::ApnsClient, close: nil) }
  let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }
  let(:sender) { ::Gitlab::MobilePush::Sender.new }
  # Wednesday 09:00 in Berlin, the start of the schedule below.
  let(:now) { Time.utc(2026, 10, 7, 7, 0) }
  let(:hold) { ::Gitlab::MobilePush::WorkingHoursHold }

  subject(:resume) { travel_to(now) { described_class.new(user, sender: sender).resume } }

  before do
    allow(::Gitlab::MobilePush::ApnsClient).to receive(:new).and_return(client)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:mobile_push_notifications_total, anything)
      .and_return(counter)

    user.user_preference.update!(
      mobile_push_working_hours_enabled: true,
      mobile_push_working_hours_start: 9 * 60,
      mobile_push_working_hours_end: 17 * 60,
      mobile_push_working_days: %w[monday tuesday wednesday thursday friday],
      mobile_push_working_hours_time_zone: 'Europe/Berlin'
    )
  end

  # The common case: one phone and one pending to-do.
  def register_phone_and_todo
    create(:mobile_device_push_subscription, user: user)
    create(:todo, user: user, project: project)
  end

  it 'sends the generic summary with the pending badge' do
    subscription = create(:mobile_device_push_subscription, user: user)
    create_list(:todo, 2, user: user, project: project)

    expect(client).to receive(:push) do |sub, payload|
      expect(sub).to eq(subscription)
      expect(payload).to be_a(::Gitlab::MobilePush::SummaryPayload)
      expect(payload.body).to eq('You have new to-dos')
      expect(payload.badge).to eq(2)

      :delivered
    end

    expect(resume).to eq(:delivered)
    expect(counter).to have_received(:increment).with(result: 'working_hours_summary')
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  it 'pushes to every registered phone' do
    create_list(:mobile_device_push_subscription, 2, user: user)
    create(:todo, user: user, project: project)
    allow(client).to receive(:push).and_return(:delivered)

    expect(resume).to eq(:delivered)
    expect(client).to have_received(:push).twice
  end

  it 'skips the summary when no to-do is pending any more' do
    create(:mobile_device_push_subscription, user: user)

    expect(client).not_to receive(:push)

    expect(resume).to eq(:skipped_nothing_pending)
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  it 'reschedules to the next opening instead of sending when the window is closed by now' do
    register_phone_and_todo
    # The user dropped Wednesday from their working days after the skip.
    user.user_preference.update!(mobile_push_working_days: %w[monday tuesday thursday friday])

    expect(client).not_to receive(:push)

    expect(resume).to eq(:rescheduled)
    expect(hold.due_user_ids(now, limit: 10)).to be_empty
    # Thursday 09:00 in Berlin.
    expect(hold.due_user_ids(Time.utc(2026, 10, 8, 7, 0), limit: 10)).to eq([user.id])
  end

  it 'drops the user when the window is closed and no next opening can be computed' do
    register_phone_and_todo
    user.user_preference.update!(mobile_push_working_days: %w[monday tuesday thursday friday])
    allow(user.user_preference).to receive(:mobile_push_next_window_start).and_return(nil)

    expect(client).not_to receive(:push)

    expect(resume).to eq(:dropped_no_window)
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  it 'reschedules to the next window when every push fails, so the summary is not lost' do
    register_phone_and_todo
    allow(client).to receive(:push).and_return(:failed)

    expect(resume).to eq(:rescheduled)
    expect(counter).to have_received(:increment).with(result: 'failed')
    # Thursday 09:00 in Berlin.
    expect(hold.due_user_ids(Time.utc(2026, 10, 8, 7, 0), limit: 10)).to eq([user.id])
  end

  it 'counts the summary as delivered when at least one phone receives it' do
    create_list(:mobile_device_push_subscription, 2, user: user)
    create(:todo, user: user, project: project)
    allow(client).to receive(:push).and_return(:failed, :delivered)

    expect(resume).to eq(:delivered)
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  it 'destroys the subscription, counts an eviction and does not retry on a dead token' do
    subscription = create(:mobile_device_push_subscription, user: user)
    create(:todo, user: user, project: project)
    allow(client).to receive(:push).and_return(:bad_token)

    expect(resume).to eq(:evicted)
    expect(Notifications::MobileDevicePushSubscription.exists?(subscription.id)).to be(false)
    expect(counter).to have_received(:increment).with(result: 'evicted')
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  it 'counts the summary as skipped and does not retry when APNs is not configured' do
    register_phone_and_todo
    allow(client).to receive(:push).and_return(:skipped)

    expect(resume).to eq(:skipped_not_configured)
    expect(counter).to have_received(:increment).with(result: 'skipped_not_configured')
    expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
  end

  context 'when a gate no longer holds' do
    before do
      register_phone_and_todo
    end

    shared_examples 'drops the user without sending' do |outcome|
      it "sends nothing and reports #{outcome}" do
        expect(client).not_to receive(:push)

        expect(resume).to eq(outcome)
        expect(hold.due_user_ids(now + 7.days, limit: 10)).to be_empty
        expect(counter).not_to have_received(:increment)
      end
    end

    context 'when the schedule was turned off overnight' do
      before do
        user.user_preference.update!(mobile_push_working_hours_enabled: false)
      end

      it_behaves_like 'drops the user without sending', :skipped_schedule_disabled
    end

    context 'when the user was blocked' do
      before do
        user.block!
      end

      it_behaves_like 'drops the user without sending', :skipped_user_inactive
    end

    context 'when the phones were unregistered' do
      before do
        user.mobile_device_push_subscriptions.delete_all
      end

      it_behaves_like 'drops the user without sending', :skipped_no_subscription
    end
  end
end
