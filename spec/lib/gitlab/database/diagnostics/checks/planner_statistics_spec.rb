# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Diagnostics::Checks::PlannerStatistics, feature_category: :database do
  describe '#execute' do
    using RSpec::Parameterized::TableSyntax

    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }

    let(:stats_reset) { nil }
    let(:never_analyzed_rows) { [] }
    let(:partitioned_rows) { [] }

    # Table name => analyze_interval of the strategy the partition manager runs it with.
    let(:registered_intervals) { { 'p_ci_builds' => 3.days, 'web_hook_logs_daily' => 1.week } }
    let(:registered_model) { Struct.new(:table_name, :partitioning_strategy) }

    subject(:result) { described_class.new(connection).execute }

    before do
      allow(connection).to receive(:select_value)
        .with(described_class::STATS_RESET_SQL).and_return(stats_reset)
      allow(connection).to receive(:select_all)
        .with(described_class::NEVER_ANALYZED_TABLES_SQL).and_return(never_analyzed_rows)
      allow(connection).to receive(:select_all)
        .with(described_class::PARTITIONED_TABLES_SQL).and_return(partitioned_rows)

      registered = registered_intervals.map do |table_name, interval|
        strategy = instance_double(Gitlab::Database::Partitioning::SlidingListStrategy, analyze_interval: interval)

        registered_model.new(table_name, strategy)
      end

      allow(Gitlab::Database::Partitioning).to receive(:registered_for_sync).and_return(registered)
    end

    # Rows as the adapter returns them: bigint and float columns are already cast.
    def table_row(name, heap_bytes:, modifications: 0)
      {
        'schema_name' => 'public', 'table_name' => name, 'heap_bytes' => heap_bytes,
        'modifications_since_analyze' => modifications,
        'last_analyze' => nil, 'last_autoanalyze' => nil, 'analyze_age_seconds' => nil
      }
    end

    def partitioned_row(name, heap_bytes:, reltuples: 1000.0, age: 1.hour)
      analyzed_at = age && (Time.current - age)

      {
        'schema_name' => 'public', 'table_name' => name, 'heap_bytes' => heap_bytes, 'reltuples' => reltuples,
        'last_analyze' => analyzed_at, 'last_autoanalyze' => nil, 'analyze_age_seconds' => age&.to_i
      }
    end

    it 'reports nothing when no relation reaches the size floor', :aggregate_failures do
      never_analyzed_rows << table_row('tiny', heap_bytes: 1.megabyte)
      partitioned_rows << partitioned_row('p_ci_builds', heap_bytes: 2.megabytes, reltuples: -1.0, age: nil)

      expect(result).to eq(stats_reset: nil, relations: [], findings: [], severity: nil, counts: {})
    end

    context 'with a stats reset' do
      let(:stats_reset) { Time.zone.parse('2026-10-01 00:00:00 UTC') }

      it 'passes the timestamp through' do
        expect(result[:stats_reset]).to eq(stats_reset)
      end
    end

    context 'with a large table that was never analyzed' do
      let(:never_analyzed_rows) { [table_row('ci_builds', heap_bytes: 20.megabytes, modifications: 42)] }

      it 'reports an error and lists the table', :aggregate_failures do
        expect(result[:relations]).to eq([{
          schema_name: 'public',
          table_name: 'ci_builds',
          kind: 'table',
          heap_bytes: 20.megabytes,
          last_analyze: nil,
          last_autoanalyze: nil,
          analyze_age_seconds: nil,
          modifications_since_analyze: 42,
          status: 'missing'
        }])

        expect(result[:findings]).to contain_exactly(a_hash_including(severity: 'error', code: 'statistics_missing'))
        expect(result[:findings].first[:message]).to include('1 large table has')
        expect(result[:severity]).to eq('error')
        expect(result[:counts]).to eq('error' => 1)
      end
    end

    context 'with a partitioned table that was never analyzed' do
      let(:partitioned_rows) { [partitioned_row('p_ci_builds', heap_bytes: 20.megabytes, reltuples: -1.0, age: nil)] }

      it 'reports it as missing with an unknown row count', :aggregate_failures do
        expect(result[:relations].first).to include(
          kind: 'partitioned_table', estimated_rows: nil, analyze_interval: 3.days.to_i, status: 'missing'
        )
        expect(result[:findings].pluck(:code)).to eq(%w[statistics_missing])
      end
    end

    context 'with partitioned tables analyzed within their interval' do
      let(:partitioned_rows) do
        [
          partitioned_row('p_ci_builds', heap_bytes: 20.megabytes, reltuples: 1234.0, age: 2.days),
          partitioned_row('issue_search_data', heap_bytes: 15.megabytes, age: 10.days)
        ]
      end

      it 'lists them without a finding', :aggregate_failures do
        expect(result[:relations].first).to include(
          schema_name: 'public',
          table_name: 'p_ci_builds',
          kind: 'partitioned_table',
          heap_bytes: 20.megabytes,
          estimated_rows: 1234,
          last_analyze: partitioned_rows.first['last_analyze'],
          analyze_age_seconds: 2.days.to_i,
          analyze_interval: 3.days.to_i,
          status: nil
        )
        expect(result[:relations].last)
          .to include(table_name: 'issue_search_data', analyze_interval: 1.week.to_i, status: nil)
        expect(result[:findings]).to be_empty
      end
    end

    context 'when the age of the statistics crosses twice the expected interval' do
      # An unregistered table is held to the default interval the manager would use.
      where(:table_name, :age, :status) do
        'p_ci_builds'         | 5.days  | nil
        'p_ci_builds'         | 7.days  | 'stale'
        'web_hook_logs_daily' | 13.days | nil
        'web_hook_logs_daily' | 15.days | 'stale'
        'issue_search_data'   | 13.days | nil
        'issue_search_data'   | 15.days | 'stale'
      end

      with_them do
        let(:partitioned_rows) { [partitioned_row(table_name, heap_bytes: 20.megabytes, age: age)] }

        it 'judges staleness against that interval', :aggregate_failures do
          expect(result[:relations].first[:status]).to eq(status)
          expect(result[:findings].pluck(:code)).to eq(status ? %w[partitioned_statistics_stale] : [])
        end
      end
    end

    context 'when the analyze timestamps were lost to a stats reset' do
      let(:partitioned_rows) { [partitioned_row('p_ci_builds', heap_bytes: 20.megabytes, age: nil)] }

      it 'does not call the table stale', :aggregate_failures do
        expect(result[:relations].first).to include(analyze_age_seconds: nil, status: nil)
        expect(result[:findings]).to be_empty
      end
    end

    context 'with a stale partitioned table' do
      let(:partitioned_rows) { [partitioned_row('p_ci_builds', heap_bytes: 20.megabytes, age: 7.days)] }

      it 'reports a warning', :aggregate_failures do
        expect(result[:findings]).to contain_exactly(
          a_hash_including(severity: 'warning', code: 'partitioned_statistics_stale')
        )
        expect(result[:findings].first[:message]).to include('1 partitioned table was')
        expect(result[:severity]).to eq('warning')
      end
    end

    context 'with more problems than the relations limit' do
      let(:never_analyzed_rows) { [table_row('ci_builds', heap_bytes: 15.megabytes)] }

      let(:partitioned_rows) do
        [
          partitioned_row('web_hook_logs_daily', heap_bytes: 100.megabytes, age: 1.day),
          partitioned_row('p_ci_builds', heap_bytes: 30.megabytes, age: 7.days),
          partitioned_row('issue_search_data', heap_bytes: 12.megabytes, reltuples: -1.0, age: nil)
        ]
      end

      before do
        stub_const("#{described_class}::RELATIONS_LIMIT", 2)
      end

      it 'lists problems first, largest first, and counts beyond the limit', :aggregate_failures do
        expect(result[:relations].pluck(:table_name)).to eq(%w[ci_builds issue_search_data])
        expect(result[:findings].pluck(:code)).to eq(%w[statistics_missing partitioned_statistics_stale])
        expect(result[:findings].first[:message]).to include('2 large tables have')
        expect(result[:counts]).to eq('error' => 1, 'warning' => 1)
      end
    end

    context 'when the never-analyzed query stops at its candidate limit' do
      let(:never_analyzed_rows) do
        [table_row('ci_builds', heap_bytes: 20.megabytes), table_row('ci_stages', heap_bytes: second_size)]
      end

      before do
        stub_const("#{described_class}::CANDIDATE_LIMIT", 2)
      end

      # Candidates are the largest heaps, so a candidate under the floor proves
      # no table beyond the limit is above it.
      where(:second_size, :message) do
        20.megabytes | 'At least 2 large tables have no planner statistics'
        1.megabyte   | '1 large table has no planner statistics'
      end

      with_them do
        it 'says "at least" only when more tables may follow' do
          expect(result[:findings].first[:message]).to start_with(message)
        end
      end
    end

    context 'with a table at the size floor' do
      where(:heap_bytes, :relation_count) do
        10_485_760 | 1
        10_485_759 | 0
      end

      with_them do
        let(:never_analyzed_rows) { [table_row('t', heap_bytes: heap_bytes)] }

        it 'treats 10 MiB as the first size reported' do
          expect(result[:relations].size).to eq(relation_count)
        end
      end
    end
  end

  # Uses the real connection, so it sits outside the stubbed describe above.
  describe 'the catalog queries' do
    let(:connection) { ApplicationRecord.connection }

    # An `around` hook runs before the transactional fixture, so this DDL is committed; the
    # schema is dropped before as well as after, so an interrupted run cannot break the next.
    around do |example|
      drop_test_schema
      connection.execute(<<~SQL)
        CREATE SCHEMA planner_stats_test;
        CREATE TABLE planner_stats_test._test_plain (id bigint, payload text);
        CREATE TABLE planner_stats_test._test_parent (id bigint, payload text) PARTITION BY RANGE (id);
        CREATE TABLE planner_stats_test._test_leaf PARTITION OF planner_stats_test._test_parent
          FOR VALUES FROM (MINVALUE) TO (MAXVALUE);
        INSERT INTO planner_stats_test._test_plain SELECT g, repeat('x', 100) FROM generate_series(1, 20000) g;
        INSERT INTO planner_stats_test._test_parent SELECT g, repeat('x', 100) FROM generate_series(1, 20000) g;
      SQL
      example.run
    ensure
      drop_test_schema
    end

    def never_analyzed_tables
      connection.select_all(described_class::NEVER_ANALYZED_TABLES_SQL).to_a
        .select { |row| row['schema_name'] == 'planner_stats_test' }
        .to_h { |row| [row['table_name'], row['heap_bytes']] }
    end

    def partitioned_table
      connection.select_all(described_class::PARTITIONED_TABLES_SQL).to_a
        .find { |row| row['schema_name'] == 'planner_stats_test' }
    end

    def heap_bytes(table_name)
      connection.select_value("SELECT pg_relation_size('planner_stats_test.#{table_name}')")
    end

    # Inserts alone leave reltuples at -1; ANALYZE on the parent records a row
    # count for the parent and its partitions, not for the table that stands alone.
    it 'lists the heap size of every table without a row count on record', :aggregate_failures do
      expect(heap_bytes('_test_leaf')).to be > 0
      expect(never_analyzed_tables)
        .to eq('_test_plain' => heap_bytes('_test_plain'), '_test_leaf' => heap_bytes('_test_leaf'))
      expect(partitioned_table).to include(
        'table_name' => '_test_parent', 'reltuples' => -1.0, 'heap_bytes' => heap_bytes('_test_leaf')
      )

      connection.execute('ANALYZE planner_stats_test._test_parent')

      expect(never_analyzed_tables.keys).to eq(%w[_test_plain])
      expect(partitioned_table['reltuples']).to eq(20_000.0)
    end

    def drop_test_schema
      connection.execute('DROP SCHEMA IF EXISTS planner_stats_test CASCADE')
    end
  end
end
