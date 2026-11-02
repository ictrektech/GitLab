# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::PgAsh::Report, feature_category: :database do
  using RSpec::Parameterized::TableSyntax

  let(:connection) { ApplicationRecord.connection }
  let(:window) { Time.utc(2026, 10, 15, 9, 0)..Time.utc(2026, 10, 15, 10, 0) }
  let(:top_queries_sql) { /'query_id', since => [^)]*::timestamptz, database => current_database\(\), n => 10/ }

  subject(:report) { described_class.new(window, connection) }

  before do
    allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, /SET LOCAL statement_timeout/).and_return([])
    allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, /FROM pg_extension/).and_return([])
  end

  def stub_reader(sql_pattern, rows)
    allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, sql_pattern).and_return(rows)
  end

  def query_row(key, pct)
    { 'key' => key, 'avg_aas' => BigDecimal('0.04'), 'peak_aas' => BigDecimal('2.4'), 'p99_aas' => nil,
      'pct' => BigDecimal(pct) }
  end

  shared_examples 'a read of the window on the main database on the primary' do
    it 'runs on the primary in a transaction with a statement timeout', :aggregate_failures do
      allow(Gitlab::Metrics::System).to receive(:monotonic_time).and_return(100.0)
      expect(Gitlab::Database::LoadBalancing::SessionMap.current(connection.load_balancer))
        .to receive(:use_primary).at_least(:once).and_call_original
      expect(connection).to receive(:transaction).at_least(:once).and_call_original

      read

      expect(Gitlab::Database::PgAsh).to have_received(:execute)
        .with(connection, "SET LOCAL statement_timeout TO '4500ms'").at_least(:once)
      expect(Gitlab::Database::PgAsh).to have_received(:execute).with(connection, a_string_including(
        "since => '2026-10-15T09:00:00Z'::timestamptz, until => '2026-10-15T10:00:00Z'::timestamptz",
        'database => current_database()'
      )).at_least(:once)
    end
  end

  describe '.window' do
    let(:now) { Time.utc(2026, 10, 15, 10, 0, 42) }

    it 'defaults an overview to the 61 minutes ending a minute back, so pg_ash reads its rollups' do
      expect(described_class.window(described_class::OVERVIEW, now: now))
        .to eq(Time.utc(2026, 10, 15, 8, 58)..Time.utc(2026, 10, 15, 9, 59))
    end

    it 'ends the default overview at the latest end when the rollups lag' do
      expect(described_class.window(described_class::OVERVIEW, latest_end: Time.utc(2026, 10, 15, 9, 40), now: now))
        .to eq(Time.utc(2026, 10, 15, 8, 39)..Time.utc(2026, 10, 15, 9, 40))
    end

    it 'defaults a drill-down to the 5 minutes ending a minute back' do
      expect(described_class.window(described_class::DRILL_DOWN, now: now))
        .to eq(Time.utc(2026, 10, 15, 9, 54)..Time.utc(2026, 10, 15, 9, 59))
    end

    it 'aligns an explicit window to the minute' do
      expect(described_class.window(
        described_class::DRILL_DOWN, from: '2026-10-15T09:54:30Z', to: '2026-10-15T09:59:30+00:00', now: now
      )).to eq(Time.utc(2026, 10, 15, 9, 54)..Time.utc(2026, 10, 15, 9, 59))
    end

    it 'accepts an overview of up to 24 hours' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-14T09:59:00Z', to: '2026-10-15T09:59:00Z', now: now
      )).to eq(Time.utc(2026, 10, 14, 9, 59)..Time.utc(2026, 10, 15, 9, 59))
    end

    it 'ends a window that ends after the latest end at the latest end, keeping its start' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-15T06:00:00Z', to: '2026-10-15T12:00:00Z',
        latest_end: Time.utc(2026, 10, 15, 9, 40), now: now
      )).to eq(Time.utc(2026, 10, 15, 6, 0)..Time.utc(2026, 10, 15, 9, 40))
    end

    it 'ends a window that ends in the current minute a minute back' do
      expect(described_class.window(
        described_class::DRILL_DOWN, from: '2026-10-15T09:56:00Z', to: '2026-10-15T10:00:00Z', now: now
      )).to eq(Time.utc(2026, 10, 15, 9, 56)..Time.utc(2026, 10, 15, 9, 59))
    end

    it 'starts an overview of an hour or less earlier, so pg_ash reads its rollups' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-15T09:20:00Z', to: '2026-10-15T09:40:00Z', now: now
      )).to eq(Time.utc(2026, 10, 15, 8, 39)..Time.utc(2026, 10, 15, 9, 40))
    end

    it 'keeps the shortest overview after ending it at the latest end' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-15T08:40:00Z', to: '2026-10-15T09:41:00Z',
        latest_end: Time.utc(2026, 10, 15, 9, 40), now: now
      )).to eq(Time.utc(2026, 10, 15, 8, 39)..Time.utc(2026, 10, 15, 9, 40))
    end

    it 'gives the newest window when the rollups ended before the chosen window started' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-15T09:00:42Z', to: '2026-10-15T10:00:42Z',
        latest_end: Time.utc(2026, 10, 15, 7, 0), now: now
      )).to eq(Time.utc(2026, 10, 15, 5, 59)..Time.utc(2026, 10, 15, 7, 0))
    end

    context 'when the latest end is over 30 days old' do
      let(:latest_end) { Time.utc(2026, 9, 1, 12, 0) }
      let(:newest_window) { Time.utc(2026, 9, 1, 10, 59)..Time.utc(2026, 9, 1, 12, 0) }

      it 'moves an explicit window back to it, and accepts that window again for follow-up reads' do
        chosen = described_class.window(described_class::OVERVIEW, from: '2026-10-15T06:00:00Z',
          to: '2026-10-15T10:00:00Z', latest_end: latest_end, now: now)
        echoed = described_class.window(described_class::OVERVIEW, from: chosen.begin.iso8601,
          to: chosen.end.iso8601, latest_end: latest_end, now: now)

        expect([chosen, echoed]).to all(eq(newest_window))
      end

      it "counts a drill-down's 30 days back from the newest rollup" do
        expect(described_class.window(described_class::DRILL_DOWN, from: '2026-09-01T11:30:00Z',
          to: '2026-09-01T11:35:00Z', newest_rollup: latest_end, now: now))
          .to eq(Time.utc(2026, 9, 1, 11, 30)..Time.utc(2026, 9, 1, 11, 35))
      end

      it 'rejects a drill-down that starts over 30 days before the newest rollup' do
        expect do
          described_class.window(described_class::DRILL_DOWN, from: '2026-08-02T11:54:00Z',
            to: '2026-08-02T11:59:00Z', newest_rollup: latest_end, now: now)
        end.to raise_error(described_class::InvalidWindowError)
      end
    end

    it 'gives the newest window when the chosen window is in the future' do
      expect(described_class.window(
        described_class::OVERVIEW, from: '2026-10-15T10:30:00Z', to: '2026-10-15T11:00:00Z', now: now
      )).to eq(Time.utc(2026, 10, 15, 8, 58)..Time.utc(2026, 10, 15, 9, 59))
    end

    where(:case_name, :kind, :from, :to) do
      'only from'                   | :overview   | '2026-10-15T08:00:00Z' | nil
      'only to'                     | :overview   | nil                    | '2026-10-15T09:59:00Z'
      'not ISO 8601'                | :overview   | 'yesterday'            | 'today'
      'not a string'                | :overview   | ['2026-10-15T08:00Z']  | '2026-10-15T09:59:00Z'
      'end before start'            | :drill_down | '2026-10-15T09:59:00Z' | '2026-10-15T09:55:00Z'
      'empty after aligning'        | :drill_down | '2026-10-15T09:55:10Z' | '2026-10-15T09:55:50Z'
      'overview over 24 hours'      | :overview   | '2026-10-14T09:58:00Z' | '2026-10-15T09:59:00Z'
      'drill-down over 5 minutes'   | :drill_down | '2026-10-15T09:53:00Z' | '2026-10-15T09:59:00Z'
      'starts over 30 days back'    | :drill_down | '2026-09-15T09:54:00Z' | '2026-09-15T09:59:00Z'
      'grows over 30 days back'     | :overview   | '2026-09-15T10:39:00Z' | '2026-09-15T10:59:00Z'
      'year zero'                   | :drill_down | '0000-01-01T00:00:00Z' | '0000-01-01T00:05:00Z'
    end

    with_them do
      it 'rejects the window' do
        expect { described_class.window(described_class.const_get(kind.upcase, false), from: from, to: to, now: now) }
          .to raise_error(described_class::InvalidWindowError)
      end
    end
  end

  describe '.rollup_watermark' do
    it 'reads the end of the minute rollups on the primary' do
      expect(Gitlab::Database::LoadBalancing::SessionMap.current(connection.load_balancer))
        .to receive(:use_primary).and_call_original
      stub_reader(/last_rollup_1m_ts/, [{ 'watermark' => Time.utc(2026, 10, 15, 9, 59) }])

      expect(described_class.rollup_watermark(connection)).to eq(Time.utc(2026, 10, 15, 9, 59))
    end

    it 'is nil before the first rollup' do
      stub_reader(/last_rollup_1m_ts/, [{ 'watermark' => nil }])

      expect(described_class.rollup_watermark(connection)).to be_nil
    end

    it 'is nil when pg_ash has no config row' do
      stub_reader(/last_rollup_1m_ts/, [])

      expect(described_class.rollup_watermark(connection)).to be_nil
    end
  end

  describe 'reads' do
    before do
      stub_reader(/FROM ash.config/, [])
    end

    it 'gives each read what is left of one budget, and at least 1 ms', :aggregate_failures do
      now = 100.0
      allow(Gitlab::Metrics::System).to receive(:monotonic_time) { now }

      report.rollup_watermark
      now = 103.25
      report.rollup_watermark
      now = 105.0
      report.rollup_watermark

      expect(Gitlab::Database::PgAsh).to have_received(:execute)
        .with(connection, "SET LOCAL statement_timeout TO '4500ms'").ordered
      expect(Gitlab::Database::PgAsh).to have_received(:execute)
        .with(connection, "SET LOCAL statement_timeout TO '1250ms'").ordered
      expect(Gitlab::Database::PgAsh).to have_received(:execute)
        .with(connection, "SET LOCAL statement_timeout TO '1ms'").ordered
    end
  end

  describe '#overview' do
    subject(:read) { report.overview }

    let(:wait_rows) do
      [
        { 'key' => 'Lock', 'source' => 'rollup_1m', 'period_start' => window.begin, 'period_end' => window.end,
          'avg_aas' => BigDecimal('0.04'), 'peak_aas' => BigDecimal('2.4'), 'p99_aas' => BigDecimal('2.23'),
          'pct' => BigDecimal('40.11') },
        { 'key' => 'CPU*', 'source' => 'rollup_1m', 'period_start' => window.begin, 'period_end' => window.end,
          'avg_aas' => BigDecimal(0), 'peak_aas' => nil, 'p99_aas' => nil, 'pct' => BigDecimal('59.89') }
      ]
    end

    before do
      stub_reader(/ash\.top\( 'wait_event_type'/, wait_rows)
      stub_reader(top_queries_sql, [query_row('2056750108613291649', 60), query_row(nil, 40)])
    end

    it_behaves_like 'a read of the window on the main database on the primary'

    it 'returns what pg_ash read, the load per wait event type and the top queries' do
      expect(read).to eq(
        coverage: { from: '2026-10-15T09:00:00Z', to: '2026-10-15T10:00:00Z', source: 'rollup_1m' },
        wait_event_types: [
          { wait_event_type: 'Lock', avg_aas: 0.04, peak_aas: 2.4, p99_aas: 2.23, pct: 40.11 },
          { wait_event_type: 'CPU*', avg_aas: 0.0, peak_aas: nil, p99_aas: nil, pct: 59.89 }
        ],
        top_queries: [
          { query_id: '2056750108613291649', query_text: nil, avg_aas: 0.04, peak_aas: 2.4, p99_aas: nil, pct: 60.0 },
          { query_id: nil, query_text: nil, avg_aas: 0.04, peak_aas: 2.4, p99_aas: nil, pct: 40.0 }
        ]
      )
    end

    it 'asks for more wait event types than the pg_ash default of 10' do
      read

      expect(Gitlab::Database::PgAsh).to have_received(:execute).with(connection, a_string_including('n => 20'))
    end

    context 'when pg_ash falls back to hourly rollups' do
      let(:wait_rows) do
        [{ 'key' => 'Lock', 'source' => 'rollup_1h', 'period_start' => Time.utc(2026, 10, 15, 9),
           'period_end' => Time.utc(2026, 10, 15, 11), 'avg_aas' => BigDecimal('0.04'), 'peak_aas' => nil,
           'p99_aas' => nil, 'pct' => BigDecimal(100) }]
      end

      it 'reports the wider period pg_ash read' do
        expect(read[:coverage]).to eq(from: '2026-10-15T09:00:00Z', to: '2026-10-15T11:00:00Z', source: 'rollup_1h')
      end
    end

    context 'without samples in the window' do
      let(:wait_rows) { [] }

      it 'returns no coverage' do
        expect(read[:coverage]).to be_nil
      end
    end
  end

  describe '#queries' do
    subject(:read) { report.queries(wait_event_type: wait_event_type) }

    let(:wait_event_type) { 'Lock' }

    before do
      stub_reader(/ash\.top\( 'query_id'/, [query_row('-7134873239275742000', 90), query_row(nil, 10)])
    end

    it_behaves_like 'a read of the window on the main database on the primary'

    it 'returns the queries behind the wait event type, with query IDs as strings' do
      expect(read).to eq([
        { query_id: '-7134873239275742000', query_text: nil, avg_aas: 0.04, peak_aas: 2.4, p99_aas: nil, pct: 90.0 },
        { query_id: nil, query_text: nil, avg_aas: 0.04, peak_aas: 2.4, p99_aas: nil, pct: 10.0 }
      ])
    end

    context 'when the wait event type contains SQL' do
      let(:wait_event_type) { "Lock'); SELECT pg_sleep(5); --" }

      it 'passes it as a quoted literal #security' do
        read

        expect(Gitlab::Database::PgAsh).to have_received(:execute)
          .with(connection, a_string_including("wait_event_type => 'Lock''); SELECT pg_sleep(5); --'"))
      end
    end

    context 'when raw samples no longer cover the window' do
      before do
        allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, /ash\.top\( 'query_id'/).and_raise(
          ActiveRecord::StatementInvalid,
          'PG::RaiseException: ERROR:  pg_ash: this drill needs exact raw query attribution, but the requested window'
        )
      end

      it 'raises QueryDetailsUnavailableError' do
        expect { read }.to raise_error(described_class::QueryDetailsUnavailableError)
      end
    end

    context 'when the read fails for another reason' do
      before do
        allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, /ash\.top\( 'query_id'/)
          .and_raise(ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout')
      end

      it 'raises the database error' do
        expect { read }.to raise_error(ActiveRecord::QueryCanceled)
      end
    end
  end

  describe '#top_queries' do
    subject(:read) { report.top_queries }

    let(:comment) { '/*application:web,correlation_id:01AAAA,endpoint_id:GET /api/:version/projects*/ ' }
    let(:schema) { 'public' }

    before do
      stub_reader(top_queries_sql, [query_row('-7134873239275742000', 55), query_row(nil, 45)])
      stub_reader(/FROM pg_extension/, [{ 'schema' => schema }])
    end

    def stub_query_texts(rows)
      stub_reader(/\.pg_stat_statements WHERE/, rows)
    end

    it_behaves_like 'a read of the window on the main database on the primary' do
      before do
        stub_query_texts([])
      end
    end

    it 'reads the full text of the queries in this database by query ID, without the comment and capped' do
      full_text = "select #{(1..150).map { |index| "$#{index} as c#{index}" }.join(', ')}"
      stub_query_texts([{ 'query_id' => '-7134873239275742000', 'query' => "#{comment}#{full_text}" }])

      expect(read.map { |row| row[:query_text] }).to eq([full_text.truncate(described_class::QUERY_TEXT_LIMIT), nil])
      expect(Gitlab::Database::PgAsh).to have_received(:execute).with(connection, a_string_including(
        'FROM "public".pg_stat_statements',
        'dbid = (SELECT oid FROM pg_database WHERE datname = current_database())',
        'queryid = ANY(ARRAY[-7134873239275742000]::bigint[])'
      ))
    end

    it 'keeps the first text this role can see when pg_stat_statements has several rows for a query' do
      stub_query_texts([
        { 'query_id' => '-7134873239275742000', 'query' => '<insufficient privilege>' },
        { 'query_id' => '-7134873239275742000', 'query' => 'select first' },
        { 'query_id' => '-7134873239275742000', 'query' => 'select second' }
      ])

      expect(read.first[:query_text]).to eq('select first')
    end

    it 'does not look up text when no load is attributed to a query' do
      stub_reader(top_queries_sql, [query_row(nil, 100)])

      expect(read).to contain_exactly(a_hash_including(query_id: nil, query_text: nil))
      expect(Gitlab::Database::PgAsh).not_to have_received(:execute).with(connection, /FROM pg_extension/)
    end

    context 'when the extension schema needs quoting' do
      let(:schema) { 'My "ext"' }

      it 'quotes it as one identifier' do
        stub_query_texts([])

        read

        expect(Gitlab::Database::PgAsh).to have_received(:execute)
          .with(connection, a_string_including('FROM "My ""ext""".pg_stat_statements'))
      end
    end

    context 'when pg_stat_statements is not installed' do
      it 'returns the queries without text' do
        stub_reader(/FROM pg_extension/, [])

        expect(read.map { |row| row[:query_text] }).to eq([nil, nil])
        expect(Gitlab::Database::PgAsh).not_to have_received(:execute).with(connection, /pg_stat_statements WHERE/)
      end
    end

    context 'when pg_stat_statements cannot be read' do
      it 'returns the queries without text and tracks the error' do
        error = ActiveRecord::StatementInvalid.new('PG::InsufficientPrivilege: permission denied')
        allow(Gitlab::Database::PgAsh).to receive(:execute).with(connection, /\.pg_stat_statements WHERE/)
          .and_raise(error)
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

        expect(read.map { |row| row[:query_text] }).to eq([nil, nil])
      end
    end
  end

  describe '#timeline' do
    subject(:read) { report.timeline }

    before do
      stub_reader(/ash\.timeline\(/, [
        { 'bucket_start' => Time.utc(2026, 10, 15, 9, 58), 'source' => 'rollup_1m', 'avg_aas' => nil,
          'peak_aas' => nil, 'p99_aas' => nil },
        { 'bucket_start' => Time.utc(2026, 10, 15, 9, 59), 'source' => 'rollup_1m', 'avg_aas' => BigDecimal('5.58'),
          'peak_aas' => BigDecimal('5.58'), 'p99_aas' => BigDecimal('5.58') }
      ])
    end

    it_behaves_like 'a read of the window on the main database on the primary'

    it 'returns one row per bucket with ISO 8601 UTC times and sources, keeping buckets without samples as nil' do
      expect(read).to eq([
        { bucket_start: '2026-10-15T09:58:00Z', source: 'rollup_1m', avg_aas: nil, peak_aas: nil, p99_aas: nil },
        { bucket_start: '2026-10-15T09:59:00Z', source: 'rollup_1m', avg_aas: 5.58, peak_aas: 5.58, p99_aas: 5.58 }
      ])
    end

    context 'with a window of a day' do
      let(:window) { Time.utc(2026, 10, 14, 10, 0)..Time.utc(2026, 10, 15, 10, 0) }

      it 'still uses one-minute buckets' do
        read

        expect(Gitlab::Database::PgAsh).to have_received(:execute)
          .with(connection, a_string_including("bucket => interval '1 minute'"))
      end
    end

    it 'counts the load of every wait event type' do
      read

      expect(Gitlab::Database::PgAsh).not_to have_received(:execute).with(connection, /wait_event_type =>/)
    end

    context 'with a wait event type' do
      subject(:read) { report.timeline(wait_event_type: "Lock'); SELECT pg_sleep(5); --") }

      it_behaves_like 'a read of the window on the main database on the primary'

      it 'counts only its load, passing it as a quoted literal #security' do
        read

        expect(Gitlab::Database::PgAsh).to have_received(:execute)
          .with(connection, a_string_including("wait_event_type => 'Lock''); SELECT pg_sleep(5); --'"))
      end
    end
  end
end
