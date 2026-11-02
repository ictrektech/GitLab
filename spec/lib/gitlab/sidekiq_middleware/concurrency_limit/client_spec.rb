# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::ConcurrencyLimit::Client, :clean_gitlab_redis_queues, feature_category: :global_search do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestConcurrencyLimitWorker'
      end

      include ApplicationWorker

      concurrency_limit -> { 5 }

      def perform(*)
        self.class.work
      end

      def self.work; end
    end
  end

  before do
    stub_const('TestConcurrencyLimitWorker', worker_class)
    stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: false)
  end

  describe '#call' do
    context 'with an override on an otherwise unlimited worker', :clean_gitlab_redis_queues_metadata do
      let(:manager) do
        Gitlab::SidekiqMiddleware::ConcurrencyLimit::LimitManager.new(
          worker_name: worker_class.name,
          prefix: Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService::REDIS_KEY_PREFIX
        )
      end

      before do
        allow(worker_class).to receive(:get_concurrency_limit).and_return(0)
        allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
          .to receive(:has_jobs_in_queue?).with(worker_class.name).and_return(true)
        manager.set_override_limit!(2)
      end

      it 'schedules the job without reading the override' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:current_limit)
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        worker_class.perform_async('foo')

        expect(worker_class.jobs.size).to eq(1)
      end
    end

    context 'when the worker class cannot be resolved' do
      it 'schedules the job' do
        middleware = Gitlab::SidekiqMiddleware::ConcurrencyLimit::Middleware.new('UnknownWorker', { 'args' => [] })

        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)
        expect { |block| middleware.schedule(&block) }.to yield_control
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(sidekiq_concurrency_limit_middleware: false)
      end

      it 'schedules the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end
    end

    context 'when per worker feature flag is enabled' do
      before do
        stub_feature_flags(disable_sidekiq_concurrency_limit_middleware_TestConcurrencyLimitWorker: true)
      end

      it 'schedules the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(1)
      end
    end

    context 'when there are jobs in the queue' do
      before do
        allow(::Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:has_jobs_in_queue?)
                                                                                           .and_return(true)
      end

      it 'defers the job' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).to receive(:add_to_queue!).once

        TestConcurrencyLimitWorker.perform_async('foo')

        expect(TestConcurrencyLimitWorker.jobs.size).to eq(0)
      end

      it 'does not defer scheduled jobs' do
        expect(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService).not_to receive(:add_to_queue!)

        TestConcurrencyLimitWorker.perform_in(10, 'foo')
      end
    end
  end
end
