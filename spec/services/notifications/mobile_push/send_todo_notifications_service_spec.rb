# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notifications::MobilePush::SendTodoNotificationsService, feature_category: :notifications do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:todo) { create(:todo, user: user, project: project) }
  let(:client) { instance_double(::Gitlab::MobilePush::ApnsClient, close: nil) }
  let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }
  let(:histogram) { instance_double(Prometheus::Client::Histogram, observe: nil) }

  before do
    allow(::Gitlab::MobilePush::ApnsClient).to receive(:new).and_return(client)
    allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
      .with(described_class::RATE_LIMIT_KEY, scope: anything)
      .and_return(false)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:mobile_push_notifications_total, anything)
      .and_return(counter)
    allow(Gitlab::Metrics).to receive(:histogram).and_call_original
    allow(Gitlab::Metrics).to receive(:histogram)
      .with(:mobile_push_notification_delivery_seconds, anything, anything, anything)
      .and_return(histogram)
  end

  describe '#execute' do
    context 'when the todos no longer exist' do
      it 'skips and counts each missing todo' do
        expect(client).not_to receive(:push)

        described_class.new([non_existing_record_id]).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_todo_resolved')
      end
    end

    context 'when a todo is no longer pending' do
      let(:todo) { create(:todo, :done, user: user, project: project) }

      it 'skips and counts the outcome' do
        expect(client).not_to receive(:push)

        described_class.new([todo.id]).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_todo_resolved')
      end
    end

    context 'when the recipient is not an active user' do
      %i[blocked banned deactivated].each do |trait|
        it "does not push to a #{trait} user" do
          inactive_user = create(:user, trait)
          inactive_todo = create(:todo, user: inactive_user, project: project)
          create(:mobile_device_push_subscription, user: inactive_user)

          expect(client).not_to receive(:push)

          described_class.new([inactive_todo.id]).execute

          expect(counter).to have_received(:increment).with(result: 'skipped_user_inactive')
        end
      end
    end

    context 'when the user has no push subscriptions' do
      it 'skips and counts the outcome' do
        expect(client).not_to receive(:push)

        described_class.new([todo.id]).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_no_subscription')
      end
    end

    context 'when the user has push subscriptions' do
      let!(:subscription) { create(:mobile_device_push_subscription, user: user) }

      it 'pushes a full payload and records delivery metrics' do
        expect(client).to receive(:push) do |sub, payload|
          expect(sub).to eq(subscription)
          expect(payload).to be_a(::Gitlab::MobilePush::Payload)
          expect(payload).not_to be_id_only

          :delivered
        end

        described_class.new([todo.id]).execute

        expect(counter).to have_received(:increment).with(result: 'delivered')
        expect(histogram).to have_received(:observe).with({}, kind_of(Numeric))
      end

      it 'delivers every todo in the batch' do
        other_todo = create(:todo, :marked, user: user, project: project)

        expect(client).to receive(:push).twice.and_return(:delivered)

        described_class.new([todo.id, other_todo.id]).execute

        expect(counter).to have_received(:increment).with(result: 'delivered').twice
      end

      it 'returns batch tallies in the payload' do
        allow(client).to receive(:push).and_return(:delivered)

        response = described_class.new([todo.id]).execute

        expect(response).to be_success
        expect(response.payload).to eq(
          todo_count: 1,
          subscription_count: 1,
          results: { 'delivered' => 1 },
          apns_results: { 'delivered' => 1 }
        )
      end

      it 'sends an id_only payload to subscriptions in id_only mode' do
        id_only_subscription = create(:mobile_device_push_subscription, user: user, payload_mode: :id_only)

        expect(client).to receive(:push).with(subscription, anything).and_return(:delivered)
        expect(client).to receive(:push) do |sub, payload|
          expect(sub).to eq(id_only_subscription)
          expect(payload).to be_id_only

          :delivered
        end

        described_class.new([todo.id]).execute
      end

      it 'destroys the subscription and counts an eviction on a dead token' do
        expect(client).to receive(:push).with(subscription, anything).and_return(:bad_token)

        described_class.new([todo.id]).execute

        expect(Notifications::MobileDevicePushSubscription.exists?(subscription.id)).to be(false)
        expect(counter).to have_received(:increment).with(result: 'evicted')
      end

      it 'keeps the subscription and counts a failure on a transient error' do
        allow(client).to receive(:push).and_return(:failed)

        described_class.new([todo.id]).execute

        expect(Notifications::MobileDevicePushSubscription.exists?(subscription.id)).to be(true)
        expect(counter).to have_received(:increment).with(result: 'failed')
        expect(histogram).not_to have_received(:observe)
      end

      it 'counts an unconfigured APNs client separately' do
        allow(client).to receive(:push).and_return(:skipped)

        described_class.new([todo.id]).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_not_configured')
      end

      it 'closes the client after the batch' do
        allow(client).to receive(:push).and_return(:delivered)

        described_class.new([todo.id]).execute

        expect(client).to have_received(:close)
      end

      context 'when the user exceeds the push rate limit', :clean_gitlab_redis_shared_state do
        before do
          allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
            .with(described_class::RATE_LIMIT_KEY, scope: { user: user })
            .and_return(true)
        end

        it 'sends one generic summary alert on the first breach' do
          expect(client).to receive(:push) do |sub, payload|
            expect(sub).to eq(subscription)
            expect(payload).to be_a(::Gitlab::MobilePush::SummaryPayload)
            expect(payload.collapse_id).to eq("summary-#{user.id}")

            :delivered
          end

          described_class.new([todo.id]).execute

          expect(counter).to have_received(:increment).with(result: 'rate_limited')
          expect(counter).to have_received(:increment).with(result: 'delivered')
        end

        it 'suppresses alerts once the summary was sent, while still counting them' do
          allow(client).to receive(:push).and_return(:delivered)
          described_class.new([todo.id]).execute

          other_todo = create(:todo, :marked, user: user, project: project)

          response = described_class.new([other_todo.id]).execute

          expect(response.payload).to eq(
            todo_count: 1,
            subscription_count: 1,
            results: { 'rate_limited' => 1 },
            apns_results: {}
          )
          expect(client).to have_received(:push).once
          expect(counter).to have_received(:increment).with(result: 'rate_limited').twice
        end
      end

      context "when the recipient has working hours", :clean_gitlab_redis_shared_state do
        # A user of this context's own, so the schedule written here cannot
        # leak into the other examples through the shared user's cached
        # preference.
        let(:user) { create(:user) }

        before do
          user.user_preference.update!(
            mobile_push_working_hours_enabled: true,
            mobile_push_working_hours_start: 9 * 60,
            mobile_push_working_hours_end: 17 * 60,
            mobile_push_working_days: %w[monday tuesday wednesday thursday friday],
            mobile_push_working_hours_time_zone: 'Europe/Berlin'
          )
        end

        it 'skips outside them, counts, records the hold for the next window start and leaves the limiter alone' do
          expect(client).not_to receive(:push)

          travel_to(Time.utc(2026, 10, 6, 22, 0)) do # Wednesday 00:00 in Berlin
            described_class.new([todo.id]).execute
          end

          expect(counter).to have_received(:increment).with(result: 'skipped_outside_working_hours')
          expect(::Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
          # Scored with Wednesday 09:00 Berlin, 07:00 UTC.
          expect(::Gitlab::MobilePush::WorkingHoursHold.due_user_ids(Time.utc(2026, 10, 7, 6, 59), limit: 10))
            .to be_empty
          expect(::Gitlab::MobilePush::WorkingHoursHold.due_user_ids(Time.utc(2026, 10, 7, 7, 0), limit: 10))
            .to eq([user.id])
        end

        it 'hands one clock reading to the check and the hold, so the hold lands on the coming start' do
          expect(client).not_to receive(:push)
          now = Time.utc(2026, 10, 7, 6, 59, 59) # one second before 09:00 in Berlin

          travel_to(now) do
            expect_next_instance_of(::Gitlab::MobilePush::Recipient) do |recipient|
              expect(recipient).to receive(:deliver_now?).with(now).and_call_original
              expect(recipient).to receive(:next_window_start).with(now).and_call_original
            end

            described_class.new([todo.id]).execute
          end

          expect(::Gitlab::MobilePush::WorkingHoursHold.due_user_ids(now + 1.second, limit: 10)).to eq([user.id])
        end

        it 'asks skip_reason before the schedule, so a user without a phone is only counted' do
          user.mobile_device_push_subscriptions.delete_all

          travel_to(Time.utc(2026, 10, 6, 22, 0)) do
            described_class.new([todo.id]).execute
          end

          expect(counter).to have_received(:increment).with(result: 'skipped_no_subscription')
          expect(counter).not_to have_received(:increment).with(result: 'skipped_outside_working_hours')
          expect(::Gitlab::MobilePush::WorkingHoursHold.due_user_ids(Time.utc(2027, 1, 1), limit: 10)).to be_empty
        end

        it 'only counts when no next window start can be computed' do
          allow_next_found_instance_of(UserPreference) do |preference|
            allow(preference).to receive(:mobile_push_next_window_start).and_return(nil)
          end
          expect(client).not_to receive(:push)

          travel_to(Time.utc(2026, 10, 6, 22, 0)) do
            described_class.new([todo.id]).execute
          end

          expect(counter).to have_received(:increment).with(result: 'skipped_outside_working_hours')
          expect(::Gitlab::MobilePush::WorkingHoursHold.due_user_ids(Time.utc(2027, 1, 1), limit: 10)).to be_empty
        end

        it 'delivers inside them' do
          allow(client).to receive(:push).and_return(:delivered)

          travel_to(Time.utc(2026, 10, 6, 8, 0)) do # Tuesday 10:00 in Berlin
            described_class.new([todo.id]).execute
          end

          expect(client).to have_received(:push).once
          expect(counter).not_to have_received(:increment).with(result: 'skipped_outside_working_hours')
        end

        it 'delivers at any hour once the switch is off' do
          user.user_preference.update!(mobile_push_working_hours_enabled: false)
          allow(client).to receive(:push).and_return(:delivered)

          travel_to(Time.utc(2026, 10, 6, 22, 0)) do
            described_class.new([todo.id]).execute
          end

          expect(client).to have_received(:push).once
        end
      end

      it 'does not add queries per recipient for the working hours preference' do
        allow(client).to receive(:push).and_return(:delivered)

        control = ActiveRecord::QueryRecorder.new { described_class.new([todo.id]).execute }

        todos = create_list(:user, 3).map do |recipient|
          create(:mobile_device_push_subscription, user: recipient)
          create(:todo, user: recipient, project: project)
        end

        expect { described_class.new(todos.map(&:id)).execute }.not_to exceed_query_limit(control)
      end
    end
  end
end
