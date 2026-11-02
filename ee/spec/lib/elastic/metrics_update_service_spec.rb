# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Elastic::MetricsUpdateService, feature_category: :global_search do
  describe '#execute' do
    it 'sets gauges with queue sizes and oldest-item age' do
      incremental_size_gauge = instance_double(Prometheus::Client::Gauge)
      initial_size_gauge = instance_double(Prometheus::Client::Gauge)
      dead_size_gauge = instance_double(Prometheus::Client::Gauge)
      incremental_age_gauge = instance_double(Prometheus::Client::Gauge)
      initial_age_gauge = instance_double(Prometheus::Client::Gauge)

      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:search_advanced_bulk_cron_queue_size, anything, {}, :max).and_return(incremental_size_gauge)
      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:search_advanced_bulk_cron_initial_queue_size, anything, {}, :max).and_return(initial_size_gauge)
      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:search_advanced_bulk_cron_dead_queue_size, anything, {}, :max).and_return(dead_size_gauge)
      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:search_advanced_bulk_cron_queue_oldest_item_age_seconds, anything, {}, :max)
        .and_return(incremental_age_gauge)
      allow(Gitlab::Metrics).to receive(:gauge)
        .with(:search_advanced_bulk_cron_initial_queue_oldest_item_age_seconds, anything, {}, :max)
        .and_return(initial_age_gauge)

      expect(::Elastic::ProcessBookkeepingService).to receive(:queue_size).and_return(10)
      expect(::Elastic::ProcessInitialBookkeepingService).to receive(:queue_size).and_return(5)
      expect(::Search::Elastic::DeadQueue).to receive(:queue_size).and_return(42)
      expect(::Elastic::ProcessBookkeepingService).to receive(:oldest_enqueued_at).and_return(Time.current.to_f - 30)
      expect(::Elastic::ProcessInitialBookkeepingService).to receive(:oldest_enqueued_at).and_return(nil)

      expect(incremental_size_gauge).to receive(:set).with({}, 10)
      expect(initial_size_gauge).to receive(:set).with({}, 5)
      expect(dead_size_gauge).to receive(:set).with({}, 42)
      expect(incremental_age_gauge).to receive(:set).with({}, a_value_within(1).of(30))
      expect(initial_age_gauge).to receive(:set).with({}, 0.0)

      described_class.new.execute
    end

    it 'does not raise an error when queue size is zero' do
      allow(::Search::Elastic::DeadQueue).to receive(:queue_size).and_return(0)
      allow(::Elastic::ProcessBookkeepingService).to receive_messages(queue_size: 0, oldest_enqueued_at: nil)
      allow(::Elastic::ProcessInitialBookkeepingService).to receive_messages(queue_size: 0, oldest_enqueued_at: nil)

      expect { described_class.new.execute }.not_to raise_error
    end
  end
end
