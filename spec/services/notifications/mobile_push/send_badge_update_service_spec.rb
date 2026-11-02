# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notifications::MobilePush::SendBadgeUpdateService, feature_category: :notifications do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:client) { instance_double(::Gitlab::MobilePush::ApnsClient, close: nil) }
  let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

  before do
    allow(::Gitlab::MobilePush::ApnsClient).to receive(:new).and_return(client)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:mobile_push_badge_updates_total, anything)
      .and_return(counter)
  end

  describe '#execute' do
    context 'when the user no longer exists' do
      it 'skips and counts the outcome' do
        expect(client).not_to receive(:push)

        described_class.new(non_existing_record_id).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_user_inactive')
      end
    end

    context 'when the user is not active' do
      %i[blocked banned deactivated].each do |trait|
        it "does not push to a #{trait} user" do
          inactive_user = create(:user, trait)
          create(:mobile_device_push_subscription, user: inactive_user)

          expect(client).not_to receive(:push)

          described_class.new(inactive_user.id).execute

          expect(counter).to have_received(:increment).with(result: 'skipped_user_inactive')
        end
      end
    end

    context 'when the user has no push subscriptions' do
      it 'skips and counts the outcome' do
        expect(client).not_to receive(:push)

        response = described_class.new(user.id).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_no_subscription')
        expect(response.payload).to eq(
          subscription_count: 0,
          results: { 'skipped_no_subscription' => 1 },
          apns_results: {}
        )
      end
    end

    context 'when the user has push subscriptions' do
      let!(:subscription) { create(:mobile_device_push_subscription, user: user) }

      it 'pushes a badge payload carrying the current pending count' do
        create_list(:todo, 2, user: user, project: project)
        create(:todo, :done, user: user, project: project)

        expect(client).to receive(:push) do |sub, payload|
          expect(sub).to eq(subscription)
          expect(payload).to be_a(::Gitlab::MobilePush::BadgePayload)
          expect(payload.badge).to eq(2)

          :delivered
        end

        response = described_class.new(user.id).execute

        expect(counter).to have_received(:increment).with(result: 'delivered')
        expect(response.payload).to eq(
          subscription_count: 1,
          results: { 'delivered' => 1 },
          apns_results: { 'delivered' => 1 }
        )
      end

      it 'sends the same payload to every device of the user' do
        other_subscription = create(:mobile_device_push_subscription, user: user, device_token: 'b' * 64)
        payloads = []

        expect(client).to receive(:push).twice do |_sub, payload|
          payloads << payload
          :delivered
        end

        response = described_class.new(user.id).execute

        expect(payloads.uniq.size).to eq(1)
        expect(response.payload[:subscription_count]).to eq(2)
        expect(Notifications::MobileDevicePushSubscription.exists?(other_subscription.id)).to be(true)
      end

      it 'destroys the subscription and counts an eviction on a dead token' do
        expect(client).to receive(:push).with(subscription, anything).and_return(:bad_token)

        described_class.new(user.id).execute

        expect(Notifications::MobileDevicePushSubscription.exists?(subscription.id)).to be(false)
        expect(counter).to have_received(:increment).with(result: 'evicted')
      end

      it 'keeps the subscription and counts a failure on a transient error' do
        allow(client).to receive(:push).and_return(:failed)

        described_class.new(user.id).execute

        expect(Notifications::MobileDevicePushSubscription.exists?(subscription.id)).to be(true)
        expect(counter).to have_received(:increment).with(result: 'failed')
      end

      it 'counts an unconfigured APNs client separately' do
        allow(client).to receive(:push).and_return(:skipped)

        described_class.new(user.id).execute

        expect(counter).to have_received(:increment).with(result: 'skipped_not_configured')
      end

      it 'closes the client afterwards' do
        allow(client).to receive(:push).and_return(:delivered)

        described_class.new(user.id).execute

        expect(client).to have_received(:close)
      end

      it 'applies no rate limit' do
        allow(client).to receive(:push).and_return(:delivered)
        expect(::Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        described_class.new(user.id).execute
      end
    end
  end
end
