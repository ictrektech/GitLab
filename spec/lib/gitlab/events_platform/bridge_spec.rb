# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::EventsPlatform::Bridge, feature_category: :dap_event_platform do
  let(:client) { instance_double(Gitlab::Kas::Client) }
  let(:event_store) { class_double(Gitlab::EventStore, publish: nil) }
  let(:logger) { instance_double(Gitlab::EventsPlatform::Logger, info: nil, error: nil) }
  let(:proto_event) { Gitlab::Agent::Event::CloudEvent.new(id: 'event-1', type: 'com.gitlab.test.happened') }
  let(:event) { instance_double(Gitlab::EventStore::CloudEvent) }
  let(:runners) { [] }

  subject(:bridge) do
    described_class.new(topic: 'test.topic', consumer_group: 'test-group', client: client, event_store: event_store)
  end

  before do
    allow(Gitlab::EventsPlatform::Logger).to receive(:build).and_return(logger)
    allow(Gitlab::EventStore::CloudEvent).to receive(:from_proto).with(proto_event).and_return(event)
  end

  after do
    runners.each do |thread|
      thread.kill
      thread.join(1)
    end
  end

  # Runs the bridge on its own thread, so a spec can call #stop while #run blocks.
  def run_in_background
    thread = Thread.new { bridge.run }
    thread.report_on_exception = false
    runners << thread
    thread
  end

  describe '#run' do
    it 'publishes each received event and stops when asked' do
      expect(client).to receive(:subscribe_events)
        .with(topic: 'test.topic', consumer_group: 'test-group', stop_when: kind_of(Proc)) do |**, &block|
          block.call(proto_event)
          bridge.stop
        end

      bridge.run

      expect(event_store).to have_received(:publish).with(event)
      expect(logger).to have_received(:info).with(hash_including(
        message: 'events bridge published event', event_type: 'com.gitlab.test.happened', event_id: 'event-1'
      ))
      expect(logger).to have_received(:info).with(hash_including(message: 'events bridge stopped'))
    end

    context 'when publishing fails' do
      let(:error) { StandardError.new('enqueue failed') }

      before do
        allow(event_store).to receive(:publish).and_raise(error)
        allow(client).to receive(:subscribe_events) { |**, &block| block.call(proto_event) }
      end

      it 'raises from the block so the event is not acknowledged' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(error, event_type: 'com.gitlab.test.happened', event_id: 'event-1')

        expect { bridge.run }.to raise_error(error)

        expect(logger).to have_received(:error).with(hash_including(
          message: 'events bridge failed to publish event; event not acknowledged',
          event_id: 'event-1',
          error_class: 'StandardError'
        ))
      end
    end

    context 'when the event type is not registered' do
      before do
        allow(Gitlab::EventStore::CloudEvent).to receive(:from_proto)
          .and_raise(Gitlab::EventStore::CloudEvent::UnknownCloudEventTypeError)
        allow(client).to receive(:subscribe_events) { |**, &block| block.call(proto_event) }
      end

      it 'raises without publishing' do
        expect { bridge.run }.to raise_error(Gitlab::EventStore::CloudEvent::UnknownCloudEventTypeError)

        expect(event_store).not_to have_received(:publish)
      end
    end

    context 'when the subscription ends without a stop request' do
      it 'waits and subscribes again' do
        calls = 0

        allow(client).to receive(:subscribe_events) do
          calls += 1
          bridge.stop if calls == 2
        end
        expect(bridge).to receive(:sleep).with(described_class::RESUBSCRIBE_INTERVAL_SECONDS).once

        bridge.run

        expect(calls).to eq(2)
      end
    end

    it 'asks the client to stop subscribing once the feature flag is disabled' do
      allow(Feature).to receive(:disabled?).and_call_original
      allow(Feature).to receive(:disabled?).with(:subscribe_events_from_relay, :instance).and_return(false, true)

      expect(client).to receive(:subscribe_events) do |stop_when:, **|
        expect(stop_when.call).to be(false)
        expect(stop_when.call).to be(true)

        bridge.stop
      end

      bridge.run
    end

    context 'when the subscribe_events_from_relay feature flag is disabled' do
      before do
        stub_feature_flags(subscribe_events_from_relay: false)
      end

      it 'waits without subscribing' do
        expect(client).not_to receive(:subscribe_events)
        expect(bridge).to receive(:sleep).with(described_class::RESUBSCRIBE_INTERVAL_SECONDS) { bridge.stop }

        bridge.run

        expect(logger).to have_received(:info).with(hash_including(
          message: 'subscribe_events_from_relay feature flag is disabled; waiting'
        ))
      end
    end
  end

  describe '#stop' do
    it 'interrupts a stream that is waiting for events' do
      waiting = Queue.new

      allow(client).to receive(:subscribe_events) do
        waiting << true
        sleep
      end

      runner = run_in_background
      waiting.pop
      bridge.stop

      expect(runner.join(5)).to eq(runner)
      expect(logger).to have_received(:info).with(hash_including(message: 'events bridge shutting down'))
    end

    it 'lets the in-flight event finish and acknowledges it before stopping' do
      publishing = Queue.new
      finish_publish = Queue.new
      acknowledged = false

      allow(event_store).to receive(:publish) do
        publishing << true
        # connection_pool re-enables interrupts like this around every Redis call.
        Thread.handle_interrupt(Exception => :immediate) { finish_publish.pop }
      end
      allow(client).to receive(:subscribe_events) do |**, &block|
        block.call(proto_event)
        acknowledged = true
        sleep
      end

      runner = run_in_background
      publishing.pop
      bridge.stop
      sleep(described_class::STOP_CHECK_INTERVAL_SECONDS * 2)
      finish_publish << true

      expect(runner.join(5)).to eq(runner)
      expect(acknowledged).to be(true)
      expect(logger).not_to have_received(:error)
    end

    it 'leaves the next event unacknowledged when a stop was requested first' do
      allow(client).to receive(:subscribe_events) do |**, &block|
        bridge.stop
        block.call(proto_event)
      end

      bridge.run

      expect(event_store).not_to have_received(:publish)
      expect(logger).to have_received(:info).with(hash_including(message: 'events bridge shutting down'))
    end

    it 'ignores repeated stop requests' do
      waiting = Queue.new

      allow(client).to receive(:subscribe_events) do
        waiting << true
        sleep
      end

      runner = run_in_background
      waiting.pop
      bridge.stop
      bridge.stop

      expect(runner.join(5)).to eq(runner)
      expect { runner.value }.not_to raise_error
    end

    it 'does nothing before the bridge runs' do
      expect { bridge.stop }.not_to raise_error
    end
  end
end
