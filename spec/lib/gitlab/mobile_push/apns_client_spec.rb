# frozen_string_literal: true

require 'spec_helper'
require 'apnotic' # require: false in the Gemfile; the client requires it lazily

RSpec.describe Gitlab::MobilePush::ApnsClient, feature_category: :notifications do
  subject(:client) do
    described_class.new(auth_key_path: '/tmp/key.p8', key_id: 'KEYID12345', team_id: 'TEAM123456')
  end

  let(:connection) { instance_double(Apnotic::Connection, push: response, close: nil) }
  let(:response) { instance_double(Apnotic::Response, ok?: true) }
  let(:payload) do
    instance_double(
      Gitlab::MobilePush::Payload,
      title: 'T', subtitle: 'S', body: 'B', badge: 1, thread_id: 'th',
      collapse_id: 'todo-1', mutable_content?: true, gitlab_data: { version: 1 }
    )
  end

  describe 'configuration' do
    it 'reads credentials from gitlab.yml mobile_push.apns settings by default' do
      stub_config(
        mobile_push: { apns: { auth_key_path: '/tmp/key.p8', key_id: 'K', team_id: 'T', topic: 'custom.topic' } }
      )

      expect(described_class.new).to be_configured
    end

    it 'is not configured when the settings are absent' do
      expect(described_class.new).not_to be_configured
    end
  end

  describe '#push notification shape' do
    let(:subscription) { build_stubbed(:mobile_device_push_subscription, :sandbox) }
    let(:sent) { [] }

    before do
      allow(Apnotic::Connection).to receive(:development).and_return(connection)
      allow(connection).to receive(:push) do |notification|
        sent << notification
        response
      end
    end

    it 'sends an alert payload with alert, sound and default priority' do
      client.push(subscription, payload)

      expect(sent.size).to eq(1)
      notification = sent.first
      expect(notification.alert).to eq('title' => 'T', 'subtitle' => 'S', 'body' => 'B')
      expect(notification.sound).to eq('default')
      expect(notification.priority).to be_nil
      expect(notification.badge).to eq(1)
      expect(notification.apns_collapse_id).to eq('todo-1')
      expect(notification.mutable_content).to be(true)
    end

    context 'with a payload carrying no alert text' do
      let(:payload) do
        instance_double(
          Gitlab::MobilePush::BadgePayload,
          title: nil, subtitle: nil, body: nil, badge: 4, thread_id: nil,
          collapse_id: 'badge-7', mutable_content?: false, gitlab_data: { version: 1, type: 'badge' }
        )
      end

      it 'sends a badge-only notification: no alert, no sound, priority 5' do
        client.push(subscription, payload)

        expect(sent.size).to eq(1)
        notification = sent.first
        expect(notification.alert).to be_nil
        expect(notification.sound).to be_nil
        expect(notification.priority).to eq(5)
        expect(notification.badge).to eq(4)
        expect(notification.apns_collapse_id).to eq('badge-7')
        expect(notification.mutable_content).to be_nil
        expect(notification.custom_payload).to eq(gitlab: { version: 1, type: 'badge' })
      end
    end
  end

  describe '#push connection reuse' do
    it 'opens one connection per APNs environment and reuses it across pushes' do
      sandbox_one = build_stubbed(:mobile_device_push_subscription, :sandbox)
      sandbox_two = build_stubbed(:mobile_device_push_subscription, :sandbox)
      production = build_stubbed(:mobile_device_push_subscription)

      expect(Apnotic::Connection).to receive(:development).once.and_return(connection)
      expect(Apnotic::Connection).to receive(:new).once.and_return(connection)

      client.push(sandbox_one, payload)
      client.push(sandbox_two, payload)
      client.push(production, payload)
    end
  end

  describe '#push error handling' do
    let(:subscription) { build_stubbed(:mobile_device_push_subscription, :sandbox) }

    it 'returns :failed and tracks the exception when the auth key file is unreachable' do
      missing_key_client = described_class.new(
        auth_key_path: '/nonexistent/key.p8', key_id: 'KEYID12345', team_id: 'TEAM123456'
      )

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(RuntimeError), subscription_id: subscription.id)

      expect(missing_key_client.push(subscription, payload)).to eq(:failed)
    end

    it 'returns :failed and tracks the exception when delivery raises' do
      allow(Apnotic::Connection).to receive(:development).and_return(connection)
      allow(connection).to receive(:push).and_raise(SocketError)

      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(SocketError), subscription_id: subscription.id)

      expect(client.push(subscription, payload)).to eq(:failed)
    end

    it 'drops the broken connection so the next push reconnects' do
      broken = instance_double(Apnotic::Connection)
      allow(broken).to receive(:push).and_raise(SocketError)
      allow(broken).to receive(:close).and_raise(IOError)

      allow(Apnotic::Connection).to receive(:development).and_return(broken, connection)
      allow(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(client.push(subscription, payload)).to eq(:failed)
      expect(client.push(subscription, payload)).to eq(:delivered)

      expect(Apnotic::Connection).to have_received(:development).twice
      expect(broken).to have_received(:close)
    end
  end

  describe '#push APNs rejections' do
    let(:subscription) { build_stubbed(:mobile_device_push_subscription, :sandbox) }

    before do
      allow(Apnotic::Connection).to receive(:development).and_return(connection)
    end

    context 'when APNs rejects the provider token' do
      let(:response) do
        instance_double(Apnotic::Response, ok?: false, status: '403', body: { 'reason' => 'BadEnvironmentKeyInToken' })
      end

      it 'returns :failed and logs the status and reason' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(
            message: 'APNs rejected mobile push notification',
            subscription_id: subscription.id,
            apns_environment: subscription.apns_environment,
            apns_status: '403',
            apns_reason: 'BadEnvironmentKeyInToken',
            result: :failed
          )
        )

        expect(client.push(subscription, payload)).to eq(:failed)
      end
    end

    context 'when APNs reports a dead device token' do
      let(:response) do
        instance_double(Apnotic::Response, ok?: false, status: '410', body: { 'reason' => 'Unregistered' })
      end

      it 'returns :bad_token and logs the eviction at info level' do
        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(apns_status: '410', apns_reason: 'Unregistered', result: :bad_token)
        )

        expect(client.push(subscription, payload)).to eq(:bad_token)
      end
    end

    context 'when APNs does not answer' do
      let(:response) { nil }

      it 'returns :failed and logs the missing response' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(
            subscription_id: subscription.id, apns_status: nil, apns_reason: 'no response', result: :failed
          )
        )

        expect(client.push(subscription, payload)).to eq(:failed)
      end
    end
  end

  describe '#close' do
    it 'closes every opened connection' do
      subscription = build_stubbed(:mobile_device_push_subscription, :sandbox)
      allow(Apnotic::Connection).to receive(:development).and_return(connection)

      client.push(subscription, payload)
      client.close

      expect(connection).to have_received(:close)
    end
  end
end
