# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Zoekt::MetricsService, feature_category: :global_search do
  let(:service) { described_class.new(metric.to_s) }
  let(:logger) { instance_double(::Search::Zoekt::Logger) }

  subject(:execute) { service.execute }

  before do
    allow(Search::Zoekt::Logger).to receive(:build).and_return(logger)
  end

  describe '.execute' do
    let(:metric) { :foo }

    it 'executes the metric' do
      expect(described_class).to receive(:new).with(metric).and_return(service)
      expect(service).to receive(:execute)

      described_class.execute(metric)
    end
  end

  describe '#execute' do
    let(:metric) { :foo }

    it 'raises an exception when unknown metric is provided' do
      expect { service.execute }.to raise_error(ArgumentError)
    end

    it 'raises an exception when the metric is not implemented' do
      stub_const('::Search::Zoekt::MetricsService::METRICS', [:foo])

      expect { service.execute }.to raise_error(NotImplementedError)
    end
  end

  describe '#node_metrics' do
    let(:metric) { :node_metrics }
    let_it_be(:node) { create(:zoekt_node, :enough_free_space) }

    before do
      allow(logger).to receive(:info) # avoid a flaky test if there are multiple zoekt nodes
    end

    it 'logs zoekt metadata and tasks info for nodes' do
      create(:zoekt_index, zoekt_enabled_namespace: create(:zoekt_enabled_namespace), node: node)
      create(:zoekt_index, :ready, zoekt_enabled_namespace: create(:zoekt_enabled_namespace), node: node)
      create_list(:zoekt_task, 4, :pending, node: node)
      create(:zoekt_task, :done, node: node)
      create(:zoekt_task, :orphaned, node: node)
      create_list(:zoekt_task, 2, :failed, node: node)

      expect(logger).to receive(:info).with(a_hash_including(
        'class' => described_class.name,
        'meta' => a_hash_including(node.metadata_json.stringify_keys),
        'enabled_namespaces_count' => 2,
        'indices_count' => 2,
        'indices_count_pending' => 1,
        'task_count_pending' => 4,
        'task_count_failed' => 2,
        'task_count_done' => 1,
        'task_count_orphaned' => 1,
        'metric' => :node_metrics
      ))

      execute
    end
  end

  describe '#enabled_namespaces_metrics' do
    let(:metric) { :enabled_namespaces_metrics }

    it 'logs the number of enabled namespaces without replicas' do
      create(:zoekt_replica)
      create_list(:zoekt_enabled_namespace, 2)

      expect(logger).to receive(:info).with(a_hash_including(
        'class' => described_class.name,
        'meta.zoekt.enabled_namespaces_without_replicas' => 2,
        'metric' => :enabled_namespaces_metrics
      ))

      execute
    end
  end

  describe '#indices_metrics' do
    let(:metric) { :indices_metrics }

    before do
      allow(logger).to receive(:info) # avoid a flaky test if there are multiple zoekt nodes
    end

    it 'logs info for zoekt indices' do
      allow(::Search::Zoekt::Index).to receive_message_chain(
        :with_stale_used_storage_bytes_updated_at, :count
      ).and_return(8675309)

      expect(logger).to receive(:info).with(a_hash_including(
        'class' => described_class.name,
        'meta.zoekt.with_stale_used_storage_bytes_updated_at' => 8675309,
        'metric' => :indices_metrics
      ))

      execute
    end
  end

  describe '#freshness_metrics' do
    let(:metric) { :freshness_metrics }
    let(:lag_gauge) { instance_double(Prometheus::Client::Gauge) }
    let(:last_indexed_at_gauge) { instance_double(Prometheus::Client::Gauge) }
    let(:now) { Time.zone.parse('2026-09-09 12:00:00 UTC') }

    let_it_be(:node) { create(:zoekt_node, :enough_free_space) }
    let_it_be(:enabled_namespace) { create(:zoekt_enabled_namespace) }
    # zoekt_indices has a unique constraint on (zoekt_enabled_namespace_id, zoekt_node_id), so a
    # second index on the same node needs its own enabled namespace.
    let_it_be(:other_enabled_namespace) { create(:zoekt_enabled_namespace) }

    let(:labels) { { zoekt_node_id: node.id, zoekt_node_name: node.metadata['name'] } }

    before do
      allow(logger).to receive(:info)

      # The trailing argument pins the multiprocess mode, which is load-bearing: a queue depth has
      # no monotone frontier to merge, so the lag gauge must keep one series per writing process.
      allow(::Gitlab::Metrics).to receive(:gauge)
        .with(:search_zoekt_indexing_lag_seconds, anything).and_return(lag_gauge)
      allow(::Gitlab::Metrics).to receive(:gauge)
        .with(:search_zoekt_last_indexed_at_timestamp_seconds, anything, {}, :max)
        .and_return(last_indexed_at_gauge)

      allow(lag_gauge).to receive(:set)
      allow(last_indexed_at_gauge).to receive(:set)
    end

    # let_it_be fixtures are built by before(:all), OUTSIDE this hook, so they carry real
    # wall-clock timestamps; build time-sensitive fixtures inside an example instead.
    around do |example|
      travel_to(now) { example.run }
    end

    describe 'search_zoekt_indexing_lag_seconds' do
      it 'reports the age of the oldest task still in the processing queue' do
        create(:zoekt_task, :pending, node: node, perform_at: now - 90.seconds)
        create(:zoekt_task, :pending, node: node, perform_at: now - 30.seconds)

        expect(lag_gauge).to receive(:set).with(labels, 90)

        execute
      end

      it 'reports zero when the queue is drained' do
        create(:zoekt_task, :done, node: node, perform_at: now - 10.minutes)

        expect(lag_gauge).to receive(:set).with(labels, 0)

        execute
      end

      it 'ignores tasks that are not yet due' do
        create(:zoekt_task, :pending, node: node, perform_at: now + 5.minutes)

        expect(lag_gauge).to receive(:set).with(labels, 0)

        execute
      end

      it 'ignores tasks belonging to another node' do
        other_node = create(:zoekt_node, :enough_free_space)
        create(:zoekt_task, :pending, node: other_node, perform_at: now - 10.minutes)

        expect(lag_gauge).to receive(:set).with(labels, 0)

        execute
      end

      it 'registers with the default multiprocess mode so each process keeps its own series' do
        expect(::Gitlab::Metrics).to receive(:gauge)
          .with(:search_zoekt_indexing_lag_seconds, anything).and_return(lag_gauge)

        execute
      end
    end

    describe 'search_zoekt_last_indexed_at_timestamp_seconds' do
      it 'reports the timestamp of the most recent completed indexing run on the node' do
        create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node,
          last_indexed_at: now - 10.minutes)
        create(:zoekt_index, zoekt_enabled_namespace: other_enabled_namespace, node: node,
          last_indexed_at: now - 2.minutes)

        expect(last_indexed_at_gauge).to receive(:set).with(labels, (now - 2.minutes).to_i)

        execute
      end

      # Asserted as a literal, not the constant: a negative sentinel would sit below every alert
      # threshold and read as healthy, so the exact value is the property under test.
      it 'reports the epoch when no index on the node has ever been indexed' do
        create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node)

        expect(last_indexed_at_gauge).to receive(:set).with(labels, 0)

        execute
      end

      it 'excludes never-indexed indices rather than reporting them as indexed at the epoch' do
        create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node)
        create(:zoekt_index, zoekt_enabled_namespace: other_enabled_namespace, node: node,
          last_indexed_at: now - 1.minute)

        expect(last_indexed_at_gauge).to receive(:set).with(labels, (now - 1.minute).to_i)

        execute
      end

      # Only ever moving forwards is what makes the :max cross-process merge exact.
      it 'exports a value that advances as indexing progresses' do
        index = create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node,
          last_indexed_at: now - 1.hour)

        exported = []
        allow(last_indexed_at_gauge).to receive(:set) { |_labels, value| exported << value }

        # `execute` is a memoized subject, so it cannot be used for the second observation.
        service.execute
        index.update!(last_indexed_at: now)
        described_class.new(metric.to_s).execute

        expect(exported).to eq([(now - 1.hour).to_i, now.to_i])
      end

      it 'is registered with the :max multiprocess mode' do
        expect(::Gitlab::Metrics).to receive(:gauge)
          .with(:search_zoekt_last_indexed_at_timestamp_seconds, anything, {}, :max)
          .and_return(last_indexed_at_gauge)

        execute
      end
    end

    it 'labels only by node, keeping cardinality bounded' do
      create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node,
        last_indexed_at: now - 1.minute)
      create(:zoekt_task, :pending, node: node, perform_at: now - 1.minute)

      expect(lag_gauge).to receive(:set) do |actual_labels, _value|
        expect(actual_labels.keys).to contain_exactly(:zoekt_node_id, :zoekt_node_name)
      end
      expect(last_indexed_at_gauge).to receive(:set) do |actual_labels, _value|
        expect(actual_labels.keys).to contain_exactly(:zoekt_node_id, :zoekt_node_name)
      end

      execute
    end

    it "labels an unnamed node 'unnamed' rather than with an empty string" do
      unnamed_node = create(:zoekt_node, :enough_free_space, metadata: {})
      create(:zoekt_task, :pending, node: unnamed_node, perform_at: now - 1.minute)

      expect(lag_gauge).to receive(:set)
        .with({ zoekt_node_id: unnamed_node.id, zoekt_node_name: 'unnamed' }, 60)

      execute
    end

    it 'skips offline nodes' do
      offline_node = create(:zoekt_node, :offline)
      create(:zoekt_task, :pending, node: offline_node, perform_at: now - 10.minutes)

      expect(lag_gauge).not_to receive(:set)
        .with(a_hash_including(zoekt_node_id: offline_node.id), anything)

      execute
    end

    it 'logs the same values it exports' do
      create(:zoekt_index, zoekt_enabled_namespace: enabled_namespace, node: node,
        last_indexed_at: now - 3.minutes)
      create(:zoekt_task, :pending, node: node, perform_at: now - 45.seconds)

      expect(logger).to receive(:info).with(a_hash_including(
        'class' => described_class.name,
        'meta.zoekt.node_id' => node.id,
        'meta.zoekt.indexing_lag_seconds' => 45,
        'meta.zoekt.last_indexed_at_timestamp_seconds' => (now - 3.minutes).to_i,
        'metric' => :freshness_metrics
      ))

      execute
    end
  end
end
