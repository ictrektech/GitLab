# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::SyncFreshness, :clean_gitlab_redis_shared_state, :freeze_time,
  feature_category: :value_stream_management do
  let(:synced) { instance_double(Prometheus::Client::Histogram, observe: nil) }
  let(:awaiting) { instance_double(Prometheus::Client::Histogram, observe: nil) }

  before do
    allow(Gitlab::Metrics).to receive(:histogram).and_call_original
    allow(Gitlab::Metrics).to receive(:histogram)
      .with(:duo_workflow_session_credits_v2_sync_age_seconds, anything, {}, described_class::AGE_BUCKETS)
      .and_return(synced)
    allow(Gitlab::Metrics).to receive(:histogram)
      .with(:duo_workflow_session_credits_v2_awaiting_sync_seconds, anything, {}, described_class::AGE_BUCKETS)
      .and_return(awaiting)
  end

  describe '.record_completion' do
    it 'stores the completion time' do
      described_class.record_completion(42)

      expect(described_class.status(42)[:last_completed_at]).to eq(Time.zone.at(Time.current.to_i))
    end

    it 'never moves a completion back in time' do
      described_class.record_completion(42)
      later = Time.current.to_i
      travel(-1.hour)

      described_class.record_completion(42)

      expect(described_class.status(42)[:last_completed_at].to_i).to eq(later)
    end
  end

  describe 'key expiry' do
    def ttl(key)
      Gitlab::Redis::SharedState.with { |redis| redis.ttl(key) }
    end

    def shorten_ttl(key)
      Gitlab::Redis::SharedState.with { |redis| redis.expire(key, 10) }
    end

    it 'refreshes the completions TTL on every completion' do
      described_class.record_completion(42)
      shorten_ttl(described_class::COMPLETED_KEY)

      described_class.record_completion(43)

      expect(ttl(described_class::COMPLETED_KEY)).to be_within(5).of(described_class::RETENTION.to_i)
    end

    it 'refreshes the scope TTLs on every tick', :aggregate_failures do
      described_class.observe([42])
      [described_class::SEEN_KEY, described_class::ENTERED_KEY].each { |key| shorten_ttl(key) }

      described_class.observe([42])

      [described_class::SEEN_KEY, described_class::ENTERED_KEY, described_class::OBSERVED_KEY].each do |key|
        expect(ttl(key)).to be_within(5).of(described_class::RETENTION.to_i)
      end
    end
  end

  describe '.status' do
    it 'returns nils for a namespace never seen' do
      expect(described_class.status(42)).to eq(last_completed_at: nil, last_seen_in_scope_at: nil, in_scope_since: nil)
    end
  end

  describe '.observe' do
    it 'starts a namespace new to the scope as awaiting its first sync', :aggregate_failures do
      expect(described_class.observe([42]))
        .to eq(oldest_sync_age_s: 0, oldest_awaiting_sync_s: 0, namespaces_awaiting_sync: 1)

      expect(awaiting).to have_received(:observe).with({}, 0)
      expect(synced).not_to have_received(:observe)
      expect(described_class.status(42)[:in_scope_since].to_i).to eq(Time.current.to_i)
    end

    it 'counts the wait from the start of the stay until the first complete sync' do
      described_class.observe([42])
      travel(6.hours)

      expect(described_class.observe([42]))
        .to include(oldest_awaiting_sync_s: 6.hours.to_i, namespaces_awaiting_sync: 1)
    end

    it 'counts the age from the last complete sync once there is one', :aggregate_failures do
      described_class.observe([42])
      travel(1.hour)
      described_class.record_completion(42)
      travel(5.hours)

      expect(described_class.observe([42]))
        .to eq(oldest_sync_age_s: 5.hours.to_i, oldest_awaiting_sync_s: 0, namespaces_awaiting_sync: 0)
      expect(synced).to have_received(:observe).with({}, 5.hours.to_i)
    end

    it 'reports the oldest age across namespaces' do
      described_class.observe([1, 2])
      described_class.record_completion(1)
      travel(2.hours)
      described_class.record_completion(2)
      travel(1.hour)

      expect(described_class.observe([1, 2])).to include(oldest_sync_age_s: 3.hours.to_i)
    end

    it 'keeps the stay when the namespace misses one tick' do
      described_class.observe([42])
      described_class.record_completion(42)
      travel(6.hours)
      described_class.observe([1])
      travel(6.hours)

      expect(described_class.observe([42])).to include(oldest_sync_age_s: 12.hours.to_i, namespaces_awaiting_sync: 0)
    end

    context 'when the namespace misses two ticks in a row' do
      before do
        described_class.observe([42])
        described_class.record_completion(42)
        2.times do
          travel(6.hours)
          described_class.observe([1])
        end
        travel(6.hours)
      end

      it 'starts a new stay instead of reporting the old completion as stale', :aggregate_failures do
        expect(described_class.observe([42])).to include(oldest_sync_age_s: 0, namespaces_awaiting_sync: 1)
        expect(described_class.status(42)[:in_scope_since].to_i).to eq(Time.current.to_i)
      end
    end

    it 'keeps every stay through a cron outage, so the staleness is reported' do
      described_class.observe([42])
      described_class.record_completion(42)
      travel(3.days)

      expect(described_class.observe([42])).to include(oldest_sync_age_s: 3.days.to_i, namespaces_awaiting_sync: 0)
    end

    it 'treats a completion recorded before the namespace was first seen as not part of the stay' do
      described_class.record_completion(42)
      travel(1.minute)

      expect(described_class.observe([42])).to include(namespaces_awaiting_sync: 1)
    end

    it 'handles an empty scope' do
      expect(described_class.observe([]))
        .to eq(oldest_sync_age_s: 0, oldest_awaiting_sync_s: 0, namespaces_awaiting_sync: 0)
    end

    it 'reads and writes in batches without dropping a namespace' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      expect(described_class.observe([1, 2, 3])).to include(namespaces_awaiting_sync: 3)
    end

    it 'drops namespaces out of scope for longer than the retention', :aggregate_failures do
      described_class.observe([1])
      described_class.record_completion(1)
      travel(described_class::RETENTION + 1.day)

      described_class.observe([2])

      expect(described_class.status(1)).to eq(last_completed_at: nil, last_seen_in_scope_at: nil, in_scope_since: nil)
      expect(described_class.status(2)[:last_seen_in_scope_at]).to be_present
    end

    it 'drops completions older than the retention for namespaces never seen' do
      described_class.record_completion(1)
      travel(described_class::RETENTION + 1.day)

      described_class.observe([2])

      expect(described_class.status(1)[:last_completed_at]).to be_nil
    end

    context 'when Redis is down' do
      before do
        allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(Redis::ConnectionError, 'down')
      end

      it 'tracks the error and returns nil instead of raising', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(Redis::ConnectionError))

        expect(described_class.observe([42])).to be_nil
        expect(awaiting).not_to have_received(:observe)
      end

      it 'does not raise on a completion' do
        expect { described_class.record_completion(42) }.not_to raise_error
      end
    end

    # observe calls Redis for the previous tick (1), then reads (2) and writes (3) each batch.
    context 'when Redis fails part-way through a tick' do
      where(:failing_call) { [2, 3] }

      with_them do
        before do
          calls = 0
          allow(Gitlab::Redis::SharedState).to receive(:with).and_wrap_original do |original, *args, &block|
            calls += 1
            raise Redis::ConnectionError, 'down' if calls == failing_call

            original.call(*args, &block)
          end
        end

        it 'returns nil and observes nothing' do
          expect(described_class.observe([42])).to be_nil
          expect(awaiting).not_to have_received(:observe)
        end
      end
    end
  end
end
