# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Partitioning::WithPartitioningLockRetries, feature_category: :database do
  let(:connection) { ActiveRecord::Base.retrieve_connection }
  let(:logger) { instance_spy(Gitlab::JsonLogger) }

  # takes the shortest path to a log line, so the block runs once and logs once
  let(:env) { { 'DISABLE_LOCK_RETRIES' => 'true' } }

  subject(:retries) do
    described_class.new(connection: connection, logger: logger, env: env, klass: described_class, **options)
  end

  before do
    retries.run { nil }
  end

  context 'without extra log params' do
    let(:options) { {} }

    it 'logs the caller class' do
      expect(logger).to have_received(:info).with(
        hash_including('class_name' => described_class.to_s)
      )
    end
  end

  context 'with extra log params' do
    let(:options) { { extra_log_params: { table_name: 'p_ci_builds' } } }

    it 'logs them alongside the caller class' do
      expect(logger).to have_received(:info).with(
        hash_including('class_name' => described_class.to_s, 'table_name' => 'p_ci_builds')
      )
    end
  end

  context 'with a timing configuration' do
    let(:options) { {} }
    let(:lock_timeouts) { [] }

    let(:timed_retries) do
      described_class.new(
        connection: connection,
        logger: logger,
        klass: described_class,
        timing_configuration: [[3.seconds, 0.seconds], [4.5.seconds, 0.seconds]]
      )
    end

    it 'uses it instead of the partitioning ladder' do
      allow(timed_retries).to receive(:sleep)
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute).with(/SET LOCAL lock_timeout/).and_wrap_original do |original, sql|
        lock_timeouts << sql[/'(\d+)ms'/, 1].to_i
        original.call(sql)
      end

      expect { timed_retries.run(raise_on_exhaustion: true) { raise ActiveRecord::LockWaitTimeout } }
        .to raise_error(Gitlab::Database::WithLockRetries::AttemptsExhaustedError)

      expect(lock_timeouts).to eq([3000, 4500])
    end
  end
end
