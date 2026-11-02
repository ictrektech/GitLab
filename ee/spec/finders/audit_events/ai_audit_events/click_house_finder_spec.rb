# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::AiAuditEvents::ClickHouseFinder, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }

  subject(:execute) { described_class.new(workflow: workflow).execute }

  it 'returns a ClickHouse query builder scoped to the workflow' do
    expect(execute).to be_a(::ClickHouse::Client::QueryBuilder)
    sql = execute.to_sql
    expect(sql).to include('ai_audit_events')
    expect(sql).to include(workflow.id.to_s)
    expect(sql).to match(/ORDER BY.*created_at.*DESC.*id.*DESC/im)
  end

  it 'raises when neither or both lookups are given', :aggregate_failures do
    expect { described_class.new }.to raise_error(ArgumentError)
    expect { described_class.new(workflow: workflow, ai_governance_session_id: 1) }.to raise_error(ArgumentError)
  end

  context 'with events stored in ClickHouse', :click_house do
    let(:session_id) { 11 }
    let(:started_at) { Time.utc(2026, 6, 1, 12) }

    let(:workflow_event) { event_row(workflow_id: workflow.id, created_at: started_at + 1.minute) }
    let(:session_event) { event_row(ai_governance_session_id: session_id, created_at: started_at + 2.minutes) }
    let(:earlier_session_event) { event_row(ai_governance_session_id: session_id, created_at: started_at - 1.month) }
    let(:other_session_event) { event_row(ai_governance_session_id: session_id + 1, created_at: started_at) }

    def event_row(created_at:, workflow_id: 0, ai_governance_session_id: 0)
      { id: SecureRandom.uuid, event_name: 'run_tool', created_at: created_at, workflow_id: workflow_id,
        ai_governance_session_id: ai_governance_session_id, traversal_path: '1/2/' }
    end

    def event_ids(finder)
      ::ClickHouse::Client.select(finder.execute, :main).pluck('id')
    end

    before do
      clickhouse_fixture(:ai_audit_events, [workflow_event, session_event, earlier_session_event, other_session_event])
    end

    it 'returns the events of the workflow' do
      expect(event_ids(described_class.new(workflow: workflow))).to eq([workflow_event[:id]])
    end

    it 'returns the events of the AI governance session, newest first, with the session ID' do
      rows = ::ClickHouse::Client.select(described_class.new(ai_governance_session_id: session_id).execute, :main)

      expect(rows.map { |row| row.values_at('id', 'ai_governance_session_id') }).to eq(
        [[session_event[:id], session_id], [earlier_session_event[:id], session_id]]
      )
    end

    it 'excludes events created before created_after' do
      finder = described_class.new(ai_governance_session_id: session_id, created_after: started_at)

      expect(event_ids(finder)).to eq([session_event[:id]])
    end

    describe '.counts_for_sessions' do
      it 'counts the events of each session, ignoring duplicate rows and other sessions' do
        clickhouse_fixture(:ai_audit_events, [session_event])

        expect(described_class.counts_for_sessions([session_id])).to eq(session_id => 2)
      end

      it 'excludes events created before min_created_at' do
        expect(described_class.counts_for_sessions([session_id, session_id + 1], min_created_at: started_at))
          .to eq(session_id => 1, session_id + 1 => 1)
      end

      it 'returns an empty hash without IDs' do
        expect(described_class.counts_for_sessions([])).to eq({})
      end
    end
  end

  describe '.counts_for_workflows' do
    let(:workflow_ids) { [1, 2, 3] }
    let(:ch_rows) do
      [{ 'workflow_id' => 1, 'count' => 4 }, { 'workflow_id' => 2, 'count' => 7 }]
    end

    before do
      allow(::ClickHouse::Client).to receive(:select).and_return(ch_rows)
    end

    subject(:counts) { described_class.counts_for_workflows(workflow_ids) }

    it 'returns a hash of workflow_id to count' do
      expect(counts).to eq({ 1 => 4, 2 => 7 })
    end

    it 'returns 0 implicitly for workflow IDs with no events' do
      expect(counts.key?(3)).to be(false)
    end

    it 'queries the ai_audit_events table grouped by workflow_id' do
      counts
      expect(::ClickHouse::Client).to have_received(:select) do |query, _|
        expect(query.to_sql).to include('ai_audit_events')
        expect(query.to_sql).to include('workflow_id')
      end
    end

    context 'with min_created_at' do
      let(:min_created_at) { 7.days.ago }

      subject(:counts) { described_class.counts_for_workflows(workflow_ids, min_created_at: min_created_at) }

      it 'adds a created_at lower bound to enable partition pruning' do
        counts
        expect(::ClickHouse::Client).to have_received(:select) do |query, _|
          expect(query.to_sql).to include('created_at')
        end
      end
    end
  end
end
