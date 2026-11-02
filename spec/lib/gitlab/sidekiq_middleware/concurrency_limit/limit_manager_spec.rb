# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::LimitManager, :clean_gitlab_redis_queues_metadata,
  feature_category: :scalability do
  let(:worker_class) do
    Class.new do
      def self.name
        'DummyWorker'
      end

      include ApplicationWorker
    end
  end

  let(:worker_name) { worker_class.name }
  let(:redis_key_prefix) { 'random_prefix' }
  let(:key) { "#{redis_key_prefix}:{#{worker_name.underscore}}:current_limit" }
  let(:override_key) { "#{redis_key_prefix}:{#{worker_name.underscore}}:override_limit" }

  before do
    stub_const(worker_name, worker_class)
    allow(worker_class).to receive(:get_concurrency_limit).and_return(10)
    stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_DummyWorker: false)
  end

  subject(:service) { described_class.new(worker_name: worker_name, prefix: redis_key_prefix) }

  describe '#current_limit' do
    before do
      stub_const(worker_name, worker_class)
      allow(worker_class).to receive(:get_concurrency_limit).and_return(10)
    end

    context 'when no value has been set before' do
      it 'returns the max limit value from worker attribute' do
        expect(service.current_limit).to eq(10)
      end
    end

    context 'when a value has been set before' do
      before do
        with_redis do |r|
          r.set(key, 5, ex: described_class::TTL)
        end
      end

      it 'returns the value set in Redis' do
        expect(service.current_limit).to eq(5)
      end
    end

    context 'with undefined worker' do
      before do
        hide_const(worker_name)
      end

      it 'returns 0' do
        expect(service.current_limit).to eq(0)
      end
    end
  end

  describe '#set_current_limit!' do
    it 'sets the limit in Redis with an expiry', :aggregate_failures do
      service.set_current_limit!(15)

      expect(service.current_limit).to eq(15)
      with_redis { |r| expect(r.ttl(key)).to be_between(1, described_class::TTL.to_i) }
    end

    it 'rejects an adaptive write when an override was set after the initial check', :aggregate_failures do
      service.set_current_limit!(5)
      expect(service.override_active?).to be(false)
      service.set_override_limit!(30)

      expect(service.set_current_limit!(24)).to eq(0)
      expect(service.adaptive_limit).to eq(5)
      expect(service.current_limit).to eq(30)
    end
  end

  describe '#stored_adaptive_limit' do
    it 'returns nil when no adaptive value has been stored' do
      expect(service.stored_adaptive_limit).to be_nil
    end

    it 'returns the stored adaptive value' do
      with_redis { |r| r.set(key, 5, ex: described_class::TTL) }

      expect(service.stored_adaptive_limit).to eq(5)
    end
  end

  describe '#adaptive_limit' do
    it 'falls back to the worker default when no adaptive value has been stored' do
      expect(service.adaptive_limit).to eq(10)
    end

    it 'returns the stored adaptive value' do
      with_redis { |r| r.set(key, 5, ex: described_class::TTL) }

      expect(service.adaptive_limit).to eq(5)
    end
  end

  describe '#set_override_limit!' do
    it 'rejects the worker responsible for draining deferred jobs' do
      manager = described_class.new(worker_name: 'ConcurrencyLimit::ResumeWorker', prefix: redis_key_prefix)

      expect { manager.set_override_limit!(1) }.to raise_error(described_class::InvalidOverrideError)
    end

    it 'rejects a worker name that is not the class name' do
      manager = described_class.new(worker_name: "::#{worker_name}", prefix: redis_key_prefix)

      expect { manager.set_override_limit!(20) }
        .to raise_error(described_class::InvalidOverrideError, "Use the class name #{worker_name}")
    end

    [1, 5, 30].each do |limit|
      it "enforces an override of #{limit}", :aggregate_failures do
        service.set_current_limit!(8)
        service.set_override_limit!(limit)

        expect(service.current_limit).to eq(limit)
        expect(service.adaptive_limit).to eq(8)
        expect(service.override_status).to include(limit: limit, ttl: be_between(1, 1800))
      end
    end

    [0, -1, 1.5, '10', nil].each do |limit|
      it "rejects invalid limit #{limit.inspect}" do
        expect { service.set_override_limit!(limit) }.to raise_error(described_class::InvalidOverrideError)
      end
    end

    [0, -1, 86401, 1.5, '60', nil].each do |ttl|
      it "rejects invalid TTL #{ttl.inspect}" do
        expect { service.set_override_limit!(20, ttl: ttl) }.to raise_error(described_class::InvalidOverrideError)
      end
    end

    it 'accepts a one-day override' do
      service.set_override_limit!(20, ttl: 86400)

      expect(service.override_status[:ttl]).to be_between(86398, 86400)
    end

    it 'temporarily limits an unlimited worker' do
      allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
      service.set_override_limit!(5)

      expect(service.current_limit).to eq(5)
    end

    it 'rejects a paused worker' do
      allow(worker_class).to receive(:get_concurrency_limit).and_return(-1)

      expect { service.set_override_limit!(20) }
        .to raise_error(described_class::InvalidOverrideError, 'Worker is paused')
    end

    it 'rejects a paused worker even when the global flag masks its limit' do
      allow(worker_class).to receive_messages(get_concurrency_limit: 0, configured_concurrency_limit: -1)

      expect { service.set_override_limit!(20) }.to raise_error(described_class::InvalidOverrideError)
    end

    it 'rejects an override while the global flag is off' do
      stub_feature_flags(sidekiq_concurrency_limit_middleware: false)

      expect { service.set_override_limit!(20) }.to raise_error(
        described_class::InvalidOverrideError,
        'Concurrency limits are disabled by sidekiq_concurrency_limit_middleware'
      )
    end

    it 'rejects a worker whose limits are disabled by the per-worker flag' do
      stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_DummyWorker: true)

      expect { service.set_override_limit!(20) }.to raise_error(
        described_class::InvalidOverrideError,
        'Concurrency limits are disabled for this worker by disable_sidekiq_concurrency_limit_middleware_DummyWorker'
      )
    end

    it 'names the maximum TTL in the rejection message' do
      expect { service.set_override_limit!(20, ttl: 86401) }
        .to raise_error(described_class::InvalidOverrideError, 'TTL must be an integer between 1 and 86400 seconds')
    end

    it 'logs the override' do
      expect(Sidekiq.logger).to receive(:info).with(
        a_hash_including(
          'class' => worker_name,
          'job_status' => 'concurrency_limit_override',
          'concurrency_limit_override_action' => 'set',
          'concurrency_limit_override' => 20,
          'concurrency_limit_override_ttl' => 60
        )
      )

      service.set_override_limit!(20, ttl: 60)
    end

    it 'preserves an existing override when replacement validation fails', :aggregate_failures do
      service.set_override_limit!(20)

      expect { service.set_override_limit!(0) }.to raise_error(described_class::InvalidOverrideError)
      expect(service.current_limit).to eq(20)
    end

    it 'replaces the limit and TTL', :aggregate_failures do
      service.set_override_limit!(20, ttl: 60)
      service.set_override_limit!(2, ttl: 3600)

      expect(service.current_limit).to eq(2)
      expect(service.override_status[:ttl]).to be_between(3598, 3600)
    end

    it 'rejects a non-worker class' do
      stub_const(worker_name, String)

      expect { service.set_override_limit!(20) }.to raise_error(described_class::InvalidOverrideError)
    end

    it 'rejects an unknown worker' do
      hide_const(worker_name)

      expect { service.set_override_limit!(20) }.to raise_error(described_class::InvalidOverrideError)
    end
  end

  describe 'override lifecycle' do
    before do
      service.set_current_limit!(5)
      service.set_override_limit!(20)
    end

    it 'restores the adaptive limit when cleared', :aggregate_failures do
      service.clear_override_limit!

      expect(service.current_limit).to eq(5)
      expect(service.override_active?).to be(false)
      expect(service.override_status).to eq(limit: nil, ttl: nil)
    end

    it 'logs the reset' do
      expect(Sidekiq.logger).to receive(:info).with(
        a_hash_including('class' => worker_name, 'concurrency_limit_override_action' => 'reset')
      )

      service.clear_override_limit!
    end

    it 'restores the adaptive limit when expired' do
      with_redis { |r| r.expire(override_key, 0) }

      expect(service.current_limit).to eq(5)
    end

    it 'restores the default if both values have expired' do
      with_redis { |r| r.del(override_key, key) }

      expect(service.current_limit).to eq(10)
    end

    it 'honours a subsequent pause even with a stored adaptive limit' do
      allow(worker_class).to receive(:get_concurrency_limit).and_return(-1)

      expect(service.current_limit).to eq(-1)
    end

    it 'does not enforce a limit when execution tracking is disabled' do
      # get_concurrency_limit returns 0 when the global flag is off
      allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
      stub_feature_flags(sidekiq_concurrency_limit_middleware: false)

      expect(service.current_limit).to eq(0)
    end

    it 'does not check the global flag again when the worker default is already known' do
      expect(Feature).not_to receive(:enabled?).with(:sidekiq_concurrency_limit_middleware, anything, anything)

      expect(service.current_limit).to eq(20)
    end

    it 'does not use the override as input to adaptive throttling' do
      expect(service.adaptive_limit).to eq(5)
    end
  end

  def with_redis(&block)
    Gitlab::Redis::QueuesMetadata.with(&block)
  end
end
