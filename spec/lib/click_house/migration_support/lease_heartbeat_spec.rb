# frozen_string_literal: true

require 'fast_spec_helper'
require 'redis'

RSpec.describe ClickHouse::MigrationSupport::LeaseHeartbeat, feature_category: :database do
  let(:lease) { instance_double(Gitlab::ExclusiveLeaseHelpers::SleepingLock) }
  let(:ttl) { 5.minutes }
  let(:max_duration) { 1.hour }

  subject(:heartbeat) { described_class.new(lease, ttl: ttl, interval: 0.seconds, max_duration: max_duration) }

  before do
    allow(Gitlab::AppLogger).to receive(:warn)
  end

  shared_examples 'a lost lease' do |reason|
    it 'logs the reason and raises it from ensure_held!', :aggregate_failures do
      heartbeat.call

      expect(Gitlab::AppLogger).to have_received(:warn)
        .with(hash_including('message' => 'ClickHouse migration lock lost', 'reason' => reason)).once
      expect { heartbeat.ensure_held! }.to raise_error(
        ClickHouse::MigrationSupport::Errors::LockError, /no longer held: #{reason}/
      )
    end
  end

  describe '#call' do
    it 'renews the lease until it is lost', :aggregate_failures do
      allow(lease).to receive(:renew).and_return(true, true, false)

      heartbeat.call

      expect(lease).to have_received(:renew).exactly(3).times
      expect { heartbeat.ensure_held! }.to raise_error(ClickHouse::MigrationSupport::Errors::LockError)
    end

    context 'when the lease cannot be renewed' do
      before do
        allow(lease).to receive(:renew).and_return(false)
      end

      it_behaves_like 'a lost lease', 'the lease expired or was taken over'
    end

    it 'does not renew or log once stopped', :aggregate_failures do
      allow(lease).to receive(:renew)

      heartbeat.stop
      heartbeat.call

      expect(lease).not_to have_received(:renew)
      expect(Gitlab::AppLogger).not_to have_received(:warn)
    end

    it 'raises errors other than Redis errors' do
      allow(lease).to receive(:renew).and_raise(NoMethodError)

      expect { heartbeat.call }.to raise_error(NoMethodError)
    end

    context 'when Redis fails' do
      before do
        allow(lease).to receive(:renew).and_invoke(->(*) { raise Redis::ConnectionError }, ->(*) { false })
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'tracks the error and keeps renewing', :aggregate_failures do
        heartbeat.call

        expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(an_instance_of(Redis::ConnectionError))
        expect(lease).to have_received(:renew).twice
      end

      context 'when the next renewal succeeds' do
        it 'keeps holding the lease' do
          held_after_recovery = nil
          allow(lease).to receive(:renew).and_invoke(
            ->(*) { raise Redis::ConnectionError },
            ->(*) { true },
            ->(*) {
              held_after_recovery = heartbeat.held?
              heartbeat.stop
              true
            }
          )

          heartbeat.call

          expect(held_after_recovery).to be(true)
        end
      end

      context 'when the TTL has run out since the last renewal' do
        let(:ttl) { 0.seconds }

        it 'stops renewing' do
          heartbeat.call

          expect(lease).to have_received(:renew).once
        end

        it_behaves_like 'a lost lease', 'Redis errors outlasted the lease TTL'
      end
    end

    context 'when max_duration has passed' do
      let(:max_duration) { 0.seconds }

      it 'does not renew the lease' do
        allow(lease).to receive(:renew)

        heartbeat.call

        expect(lease).not_to have_received(:renew)
      end

      it_behaves_like 'a lost lease', 'renewal reached max_duration'
    end
  end

  describe '#ensure_held!' do
    it 'does not raise while the lease is renewed' do
      expect { heartbeat.ensure_held! }.not_to raise_error
    end
  end
end
