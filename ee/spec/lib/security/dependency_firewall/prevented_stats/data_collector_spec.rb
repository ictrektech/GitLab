# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedStats::DataCollector,
  feature_category: :dependency_firewall do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:from) { (Time.current.utc.to_date - 6).beginning_of_day }

  def collect(container, requested_from = from)
    described_class.new(container: container, from: requested_from).counts
  end

  it 'reads a project through the PostgreSQL collector' do
    instance = instance_double(Security::DependencyFirewall::PreventedStats::PostgresqlCollector, counts: :stubbed)
    allow(Security::DependencyFirewall::PreventedStats::PostgresqlCollector)
      .to receive(:new).with(container: project, from: from).and_return(instance)

    expect(collect(project)).to eq(:stubbed)
  end

  it 'returns nothing for a container that is neither a project nor a group' do
    expect(collect(create(:user, :with_namespace).namespace)).to be_nil
  end

  describe 'for a group', :freeze_time do
    let!(:seven_day_stat) do
      create(:dependency_firewall_namespace_prevented_stat, namespace: group, window_days: 7,
        window_start: Date.current - 6, malicious_packages_prevented: 7)
    end

    let!(:thirty_day_stat) do
      create(:dependency_firewall_namespace_prevented_stat, namespace: group, window_days: 30,
        window_start: Date.current - 29, malicious_packages_prevented: 30)
    end

    before do
      allow(Security::DependencyFirewall::PreventedStats::PostgresqlCollector).to receive(:new)
    end

    it 'returns the 7-day row for a 7-day from' do
      expect(collect(group, (Date.current - 6).beginning_of_day)).to eq(seven_day_stat.to_counts)
    end

    it 'returns the 30-day row for a 30-day from' do
      expect(collect(group, (Date.current - 29).beginning_of_day)).to eq(thirty_day_stat.to_counts)
    end

    it 'does not read the ledger' do
      collect(group, (Date.current - 6).beginning_of_day)

      expect(Security::DependencyFirewall::PreventedStats::PostgresqlCollector).not_to have_received(:new)
    end

    it 'returns nil for a from that is not a stored window' do
      expect(collect(group, (Date.current - 9).beginning_of_day)).to be_nil
    end

    it 'returns the row even when its window_start is a day old (requested after midnight)' do
      seven_day_stat.update!(window_start: Date.current - 7)

      expect(collect(group, (Date.current - 6).beginning_of_day)).to eq(seven_day_stat.to_counts)
    end

    it 'returns nil when no row exists' do
      expect(collect(create(:group), (Date.current - 6).beginning_of_day)).to be_nil
    end

    it 'returns nil when the row is more than a day older than the current window start' do
      seven_day_stat.update!(window_start: Date.current - 8)

      expect(collect(group, (Date.current - 6).beginning_of_day)).to be_nil
    end

    it 'returns the 30-day row when its window_start is a day old' do
      thirty_day_stat.update!(window_start: Date.current - 30)

      expect(collect(group, (Date.current - 29).beginning_of_day)).to eq(thirty_day_stat.to_counts)
    end

    it 'returns nil when the 30-day row is more than a day older than the current window start' do
      thirty_day_stat.update!(window_start: Date.current - 31)

      expect(collect(group, (Date.current - 29).beginning_of_day)).to be_nil
    end

    it 'returns nil when the feature flag is disabled' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: false)

      expect(collect(group, (Date.current - 6).beginning_of_day)).to be_nil
    end

    context 'when Time.zone is ahead of UTC and the local date is already tomorrow' do
      # The parent block's :freeze_time rejects a nested travel_to block and restores the clock afterwards.
      around do |example|
        travel_to(Time.utc(2026, 1, 1, 18, 0))
        Time.use_zone('Asia/Singapore') { example.run }
      end

      it 'serves the 7-day row requested for the UTC date' do
        stat = create(:dependency_firewall_namespace_prevented_stat, namespace: create(:group), window_days: 7,
          window_start: Date.new(2025, 12, 26), malicious_packages_prevented: 3)

        expect(collect(stat.namespace, Date.new(2025, 12, 26).beginning_of_day)).to eq(stat.to_counts)
      end
    end

    context 'when scheduling group refreshes' do
      let(:refresh_worker) { Security::DependencyFirewall::RefreshGroupPreventedStatsWorker }

      it 'schedules the group when no row exists' do
        empty_group = create(:group)

        expect(refresh_worker).to receive(:schedule).with([empty_group.id])

        collect(empty_group, (Date.current - 6).beginning_of_day)
      end

      it 'schedules the group when the row is too old' do
        seven_day_stat.update!(window_start: Date.current - 8)

        expect(refresh_worker).to receive(:schedule).with([group.id])

        collect(group, (Date.current - 6).beginning_of_day)
      end

      it 'does not schedule the group when a row is served' do
        expect(refresh_worker).not_to receive(:schedule)

        collect(group, (Date.current - 6).beginning_of_day)
      end

      it 'does not schedule the group when the feature flag is disabled' do
        stub_feature_flags(dependency_firewall_group_prevented_stats: false)

        expect(refresh_worker).not_to receive(:schedule)

        collect(group, (Date.current - 6).beginning_of_day)
      end

      it 'does not schedule the group for a from that is not a stored window' do
        expect(refresh_worker).not_to receive(:schedule)

        collect(group, (Date.current - 9).beginning_of_day)
      end

      context 'when scheduling the group fails' do
        let(:empty_group) { create(:group) }
        let(:error) { Redis::CannotConnectError.new('down') }

        before do
          allow(refresh_worker).to receive(:schedule).and_raise(error)
        end

        it 'tracks the failure and still returns nil outside development' do
          expect(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
            .with(error, group_id: empty_group.id)

          expect(collect(empty_group, (Date.current - 6).beginning_of_day)).to be_nil
        end

        it 'raises in development and specs' do
          expect { collect(empty_group, (Date.current - 6).beginning_of_day) }.to raise_error(error)
        end
      end
    end
  end

  describe 'ClickHouse reads', :freeze_time, :aggregate_failures do
    let(:clickhouse_collector) { Security::DependencyFirewall::PreventedStats::ClickHouseCollector }
    let(:postgresql_collector) { Security::DependencyFirewall::PreventedStats::PostgresqlCollector }
    let(:analytics_enabled) { true }
    let(:siphon_replicating) { true }
    let(:container) { project }
    let(:collector_from) { 3.days.ago }

    subject(:counts) { collect(container, collector_from) }

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(container).and_return(analytics_enabled)
      allow(::Gitlab::ClickHouse).to receive(:siphon_enabled?)
        .with('dependency_firewall_prevented_packages').and_return(siphon_replicating)
    end

    def stubbed_counts(collector_class)
      instance = instance_double(collector_class, counts: :stubbed)
      allow(collector_class).to receive(:new).and_return(instance)
    end

    shared_examples 'reads through the ClickHouse collector' do
      it 'reads through the ClickHouse collector with the requested from' do
        stubbed_counts(clickhouse_collector)

        expect(counts).to eq(:stubbed)
        expect(clickhouse_collector).to have_received(:new).with(container: container, from: collector_from)
      end
    end

    shared_examples 'falls back when the ClickHouse read fails' do
      using RSpec::Parameterized::TableSyntax

      where(error_class: [::ClickHouse::Client::DatabaseError, Net::ReadTimeout])

      with_them do
        let(:error) { error_class.new }

        before do
          failing_read = instance_double(clickhouse_collector)
          allow(failing_read).to receive(:counts).and_raise(error)
          allow(clickhouse_collector).to receive(:new).and_return(failing_read)
        end

        it 'raises in development and specs' do
          expect { counts }.to raise_error(error.class)
        end

        it 'tracks the error and serves the PostgreSQL path outside development', :aggregate_failures do
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)

          expect(counts).to eq(fallback_counts)
          expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception)
            .with(error, container_type: container.class.name, container_id: container.id)
        end
      end
    end

    context 'for a project' do
      it_behaves_like 'reads through the ClickHouse collector'

      it 'reads through the ClickHouse collector when the flag is enabled only for the root namespace' do
        stub_feature_flags(dependency_firewall_clickhouse_reads: group)
        stubbed_counts(clickhouse_collector)

        expect(counts).to eq(:stubbed)
      end

      it 'reads through the ClickHouse collector when the group prevented stats flag is off' do
        stub_feature_flags(dependency_firewall_group_prevented_stats: false)
        stubbed_counts(clickhouse_collector)

        expect(counts).to eq(:stubbed)
      end

      shared_examples 'reads the project through PostgreSQL' do
        it 'reads through the PostgreSQL collector' do
          stubbed_counts(postgresql_collector)

          expect(counts).to eq(:stubbed)
        end
      end

      context 'when analytics ClickHouse is not enabled' do
        let(:analytics_enabled) { false }

        it_behaves_like 'reads the project through PostgreSQL'
      end

      context 'when the flag is off' do
        before do
          stub_feature_flags(dependency_firewall_clickhouse_reads: false)
        end

        it_behaves_like 'reads the project through PostgreSQL'

        it 'does not query ClickHouse to check for replication' do
          stubbed_counts(postgresql_collector)

          counts

          expect(::Gitlab::ClickHouse).not_to have_received(:siphon_enabled?)
        end
      end

      context 'when the flag is enabled only for another root namespace' do
        before do
          stub_feature_flags(dependency_firewall_clickhouse_reads: create(:group))
        end

        it_behaves_like 'reads the project through PostgreSQL'
      end

      context 'when Siphon does not replicate the ledger' do
        let(:siphon_replicating) { false }

        it_behaves_like 'reads the project through PostgreSQL'
      end

      context 'when the ClickHouse read fails' do
        let(:fallback_counts) { :stubbed }

        before do
          stubbed_counts(postgresql_collector)
        end

        it_behaves_like 'falls back when the ClickHouse read fails'
      end
    end

    context 'for a group' do
      let(:container) { group }

      it_behaves_like 'reads through the ClickHouse collector'

      context 'when the group prevented stats flag is off' do
        before do
          stub_feature_flags(dependency_firewall_group_prevented_stats: false)
        end

        it 'returns nil without reading either source' do
          stubbed_counts(clickhouse_collector)

          expect(counts).to be_nil
          expect(clickhouse_collector).not_to have_received(:new)
        end

        it 'does not query ClickHouse for the Siphon check' do
          expect(counts).to be_nil
          expect(::Gitlab::ClickHouse).not_to have_received(:siphon_enabled?)
        end
      end

      shared_examples 'reads the group through the summary table' do
        let(:collector_from) { (Date.current - 6).beginning_of_day }

        it 'serves the summary row and does not read ClickHouse' do
          stat = create(:dependency_firewall_namespace_prevented_stat, namespace: group, window_days: 7,
            window_start: Date.current - 6, malicious_packages_prevented: 7)
          allow(clickhouse_collector).to receive(:new)

          expect(counts).to eq(stat.to_counts)
          expect(clickhouse_collector).not_to have_received(:new)
        end
      end

      context 'when analytics ClickHouse is not enabled' do
        let(:analytics_enabled) { false }

        it_behaves_like 'reads the group through the summary table'
      end

      context 'when the flag is off' do
        before do
          stub_feature_flags(dependency_firewall_clickhouse_reads: false)
        end

        it_behaves_like 'reads the group through the summary table'
      end

      context 'when Siphon does not replicate the ledger' do
        let(:siphon_replicating) { false }

        it_behaves_like 'reads the group through the summary table'
      end

      context 'when the ClickHouse read fails' do
        let(:collector_from) { (Date.current - 6).beginning_of_day }
        let(:fallback_counts) { stat.to_counts }
        let!(:stat) do
          create(:dependency_firewall_namespace_prevented_stat, namespace: group, window_days: 7,
            window_start: Date.current - 6, malicious_packages_prevented: 7)
        end

        it_behaves_like 'falls back when the ClickHouse read fails'
      end
    end
  end
end
