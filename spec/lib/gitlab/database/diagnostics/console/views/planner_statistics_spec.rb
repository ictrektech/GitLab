# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Database::Diagnostics::Console::Views::PlannerStatistics, feature_category: :database do
  let(:buffer) { StringIO.new }
  let(:printer) { Gitlab::Database::Diagnostics::Console::Printer.new(output: buffer) }

  let(:stats_reset) { nil }
  let(:findings) { [] }
  let(:severity) { nil }
  let(:counts) { {} }

  let(:analyzed_partitioned_table) do
    {
      schema_name: 'public', table_name: 'p_ci_builds', kind: 'partitioned_table',
      heap_bytes: 21474836480, estimated_rows: 9000000,
      last_analyze: Time.utc(2026, 10, 20), last_autoanalyze: nil, analyze_age_seconds: 3.days.to_i,
      analyze_interval: 3.days.to_i, status: nil
    }
  end

  let(:relations) { [analyzed_partitioned_table] }

  let(:payload) do
    {
      planner_statistics: {
        stats_reset: stats_reset,
        relations: relations,
        findings: findings,
        severity: severity,
        counts: counts
      }
    }
  end

  subject(:view) { described_class.new(databases: { 'main' => payload }, printer: printer) }

  before do
    Rainbow.enabled = false
  end

  def rendered
    buffer.string.split("\n")
  end

  describe '.title' do
    it { expect(described_class.title).to eq('Planner statistics') }
  end

  describe '#run' do
    context 'with no findings' do
      it 'reports the database as clean and renders the relation', :aggregate_failures do
        expect(view.run).to eq({})

        expect(rendered.first(6)).to eq([
          '',
          '== Planner statistics ==',
          '',
          'main ... OK',
          '   Statistics reset: not recorded',
          ''
        ])
        expect(rendered[6]).to match(/^   RELATION\s+KIND\s+HEAP SIZE\s+ROWS\s+LAST ANALYZE\s+INTERVAL\s+STATUS$/)
        # GitLab's locale renders binary units (GiB); the gem default renders GB.
        expect(rendered.last)
          .to match(/^   public\.p_ci_builds\s+partitioned\s+20 Gi?B\s+~9,000,000\s+3 days ago\s+3 days\s+OK$/)
      end
    end

    context 'with findings' do
      let(:severity) { 'error' }
      let(:counts) { { 'error' => 1, 'warning' => 1 } }

      let(:findings) do
        [
          { severity: 'error', code: 'statistics_missing', message: 'No statistics.' },
          { severity: 'warning', code: 'partitioned_statistics_stale', message: 'Old statistics.' }
        ]
      end

      it 'renders the severity and counts the check supplied', :aggregate_failures do
        expect(view.run).to eq({ 'error' => 1, 'warning' => 1 })

        expect(rendered).to include('main ... 1 error, 1 warning')
        expect(rendered.grep(/^   \[/)).to eq([
          '   [error]   No statistics.',
          '   [warning] Old statistics.'
        ])
      end
    end

    context 'with a stats reset' do
      let(:stats_reset) { Time.utc(2026, 10, 1, 12, 30) }

      it 'prints when the analyze timestamps start' do
        view.run

        expect(rendered).to include('   Statistics reset: 2026-10-01T12:30:00Z')
      end
    end

    context 'with relations in every state' do
      let(:relations) do
        [
          {
            schema_name: 'public', table_name: 'ci_builds', kind: 'table', heap_bytes: 15728640,
            last_analyze: nil, last_autoanalyze: nil, analyze_age_seconds: nil,
            modifications_since_analyze: 42, status: 'missing'
          },
          analyzed_partitioned_table.merge(table_name: 'p_ci_stages', analyze_age_seconds: 7.days.to_i,
            status: 'stale'),
          analyzed_partitioned_table.merge(table_name: 'issue_search_data', analyze_age_seconds: nil,
            analyze_interval: 1.week.to_i),
          analyzed_partitioned_table.merge(table_name: 'security_findings', analyze_age_seconds: 1.day.to_i,
            analyze_interval: 1.day.to_i)
        ]
      end

      it 'distinguishes never analyzed from lost timestamps', :aggregate_failures do
        view.run

        rows = rendered.grep(/^   public\./)

        expect(rows[0]).to match(/public\.ci_builds\s+table\s+15 Mi?B\s+unknown\s+never\s+missing$/)
        expect(rows[1])
          .to match(/public\.p_ci_stages\s+partitioned\s+20 Gi?B\s+~9,000,000\s+1 week ago\s+3 days\s+stale$/)
        expect(rows[2])
          .to match(/public\.issue_search_data\s+partitioned\s+20 Gi?B\s+~9,000,000\s+unknown\s+1 week\s+OK$/)
        expect(rows[3]).to match(/public\.security_findings\s+partitioned.*1 day ago\s+1 day\s+OK$/)
      end
    end

    context 'when no relation is large enough' do
      let(:relations) { [] }

      it 'explains instead of rendering an empty table', :aggregate_failures do
        view.run

        expect(buffer.string).to include('No table or partitioned table is large enough to report.')
        expect(buffer.string).not_to include('RELATION')
      end
    end

    context 'when the collector could not read the database' do
      let(:payload) { { error: 'Failed to gather information for database: main' } }

      it 'counts an error and points at the logs for the cause', :aggregate_failures do
        expect(view.run).to eq({ 'error' => 1 })

        expect(rendered).to include(
          'main ... unavailable',
          '   Failed to gather information for database: main'
        )
        expect(buffer.string).to include('sent to the exception tracker')
      end
    end
  end
end
