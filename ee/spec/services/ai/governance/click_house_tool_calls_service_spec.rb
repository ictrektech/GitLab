# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ClickHouseToolCallsService, :click_house,
  feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  # Well before the window and its previous period, so any lower bound added to
  # the workflow lookup would drop these sessions and their events with them.
  let(:workflow_created_at) { '2026-01-15 09:00:00' }
  let(:agent_class) { :all }
  let(:container) { group }
  let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }
  let(:result) do
    described_class.new(container, current_user: user, timeframe: timeframe, agent_class: agent_class).execute
  end

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    insert_workflows([
      { id: 1 },
      { id: 2, agent_type: 'claude_code' },
      { id: 3, agent_type: 'cursor' }
    ])
    # workflow 3 deleted after the fact; the siphon keeps the row and marks it
    insert_workflows([{ id: 3, agent_type: 'cursor', deleted: true,
                        replicated_at: '2026-07-02 00:00:00' }])

    insert_events([
      { id: 1, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-06-30 10:00:00' },
      { id: 2, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-06-30 11:00:00' },
      { id: 3, workflow_id: 1, tool_name: 'run_command', created_at: '2026-06-30 12:00:00' },
      { id: 4, workflow_id: 2, tool_name: 'read_write_files', created_at: '2026-07-01 10:00:00' },
      { id: 5, workflow_id: 2, tool_name: 'run_command', created_at: '2026-07-01 11:00:00' },
      { id: 6, workflow_id: 3, tool_name: 'edit_file', created_at: '2026-07-01 12:00:00' },
      # before the window
      { id: 7, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-06-20 10:00:00' },
      # exactly on the upper bound, which is exclusive
      { id: 8, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-07-03 15:30:00' },
      # not a tool invocation
      { id: 9, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-07-01 13:00:00',
        event_name: 'ai_workflow_started' },
      # a tool invocation that recorded no tool name
      { id: 10, workflow_id: 1, created_at: '2026-07-01 14:00:00' },
      # outside the hierarchy
      { id: 11, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-07-01 15:00:00',
        path: '0/999/' }
    ])
  end

  subject(:tool_calls) { result.payload[:tool_calls] }

  it 'counts the events in the window per tool, most called first' do
    expect(tool_calls).to eq([
      { tool_name: 'read_write_files', count: 3 },
      { tool_name: 'run_command', count: 2 },
      { tool_name: 'edit_file', count: 1 }
    ])
  end

  it 'does not flag the result as approximate, since nothing is capped' do
    expect(result.payload[:approximate]).to be(false)
  end

  context 'with a project container' do
    let(:container) { project }

    it 'scopes to the project namespace traversal path' do
      expect(tool_calls).to eq([
        { tool_name: 'read_write_files', count: 3 },
        { tool_name: 'run_command', count: 2 },
        { tool_name: 'edit_file', count: 1 }
      ])
    end
  end

  context 'with more distinct tools than the top-N limit' do
    before do
      extra = (1..10).map do |index|
        { id: 100 + index, workflow_id: 1, tool_name: format('extra_%02d', index),
          created_at: '2026-07-02 09:00:00' }
      end
      insert_events(extra)
    end

    it 'returns only the busiest tools', :aggregate_failures do
      expect(tool_calls.size).to eq(Ai::Governance::ToolCallsService::TOP_N)
      # ties on one call each break by name, so the tail of the alphabet drops out
      expect(tool_calls.map { |row| row[:tool_name] }).not_to include('extra_08')
    end

    context 'with a limit' do
      let(:result) do
        described_class.new(container, current_user: user, timeframe: timeframe, limit: 1000).execute
      end

      it 'returns up to that many tools' do
        expect(tool_calls.size).to eq(13)
      end
    end
  end

  context 'when the same event is ingested twice' do
    before do
      insert_events([
        { id: 1, workflow_id: 1, tool_name: 'read_write_files', created_at: '2026-06-30 10:00:00' }
      ])
    end

    it 'counts it once, since ReplacingMergeTree collapses duplicates only on merge' do
      expect(tool_calls).to include({ tool_name: 'read_write_files', count: 3 })
    end
  end

  context 'with Claude Code tool invocations from the Compliance API' do
    before do
      # Claude Compliance API events name the tool in `details['name']`
      insert_events([
        { id: 20, workflow_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"name":"Read"}',
          created_at: '2026-07-01 16:00:00' },
        { id: 21, workflow_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"name":"Read"}',
          created_at: '2026-07-01 17:00:00' },
        { id: 22, workflow_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"name":"Bash"}',
          created_at: '2026-07-01 18:00:00' },
        # a Claude invocation that recorded no tool name
        { id: 23, workflow_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"tool_use_id":"toolu_1"}',
          created_at: '2026-07-01 19:00:00' }
      ])
    end

    it 'counts them alongside Duo tool calls under the name they carry' do
      expect(tool_calls).to eq([
        { tool_name: 'read_write_files', count: 3 },
        { tool_name: 'Read', count: 2 },
        { tool_name: 'run_command', count: 2 },
        { tool_name: 'Bash', count: 1 },
        { tool_name: 'edit_file', count: 1 }
      ])
    end

    context 'with only Claude Code invocations in the window' do
      let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_24_hours) }

      before do
        insert_events([
          { id: 24, workflow_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"name":"Read"}',
            created_at: '2026-07-03 10:00:00' }
        ])
      end

      it 'reads the tool name from details.name' do
        expect(tool_calls).to eq([{ tool_name: 'Read', count: 1 }])
      end
    end
  end

  describe 'agent_class' do
    context 'with internal_dap' do
      let(:agent_class) { :internal_dap }

      it 'keeps only events from workflows without an agent type' do
        expect(tool_calls).to eq([
          { tool_name: 'read_write_files', count: 2 },
          { tool_name: 'run_command', count: 1 }
        ])
      end
    end

    context 'with external' do
      let(:agent_class) { :external }

      it 'keeps events from workflows with an agent type, less the deleted workflow' do
        expect(tool_calls).to eq([
          { tool_name: 'read_write_files', count: 1 },
          { tool_name: 'run_command', count: 1 }
        ])
      end
    end

    context 'with an event from an external agent session' do
      before do
        insert_events([
          { id: 12, workflow_id: 0, session_id: 1, tool_name: 'edit_file', created_at: '2026-07-01 16:00:00' }
        ])
      end

      it 'counts it for all agents' do
        expect(tool_calls).to include({ tool_name: 'edit_file', count: 2 })
      end

      context 'with internal_dap' do
        let(:agent_class) { :internal_dap }

        it 'leaves it out' do
          expect(tool_calls.map { |row| row[:tool_name] }).not_to include('edit_file')
        end
      end

      context 'with external' do
        let(:agent_class) { :external }

        it 'counts it' do
          expect(tool_calls).to eq([
            { tool_name: 'edit_file', count: 1 },
            { tool_name: 'read_write_files', count: 1 },
            { tool_name: 'run_command', count: 1 }
          ])
        end
      end
    end
  end

  describe 'agent_class through governance sessions' do
    let(:sessions_enabled) { true }
    # Only the session-backed events below fall inside the last 24 hours.
    let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_24_hours) }
    let(:result) do
      described_class.new(container, current_user: user, timeframe: timeframe, agent_class: agent_class,
        sessions_enabled: sessions_enabled).execute
    end

    before do
      insert_sessions([
        { id: 1, source: :gitlab_duo },
        { id: 2, source: :gitlab_duo, agent_type: 'claude-code' },
        { id: 3, source: :claude_code_glab, agent_type: 'claude-code' }
      ])

      insert_events([
        { id: 30, session_id: 1, tool_name: 'create_issue', created_at: '2026-07-03 10:00:00' },
        { id: 31, session_id: 2, event_name: 'ai_claude_tool_invoked', details: '{"name":"Read"}',
          created_at: '2026-07-03 11:00:00' },
        { id: 32, session_id: 3, tool_name: 'Bash', created_at: '2026-07-03 12:00:00' }
      ])
    end

    it 'counts every session-backed event for all' do
      expect(tool_calls).to eq([
        { tool_name: 'Bash', count: 1 },
        { tool_name: 'Read', count: 1 },
        { tool_name: 'create_issue', count: 1 }
      ])
    end

    context 'with internal_dap' do
      let(:agent_class) { :internal_dap }

      it 'keeps only events from Duo sessions without an agent type' do
        expect(tool_calls).to eq([{ tool_name: 'create_issue', count: 1 }])
      end

      context 'with a window that also holds workflow-backed events' do
        let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }

        it 'classifies through the workflow and the session alike' do
          expect(tool_calls).to eq([
            { tool_name: 'read_write_files', count: 2 },
            { tool_name: 'create_issue', count: 1 },
            { tool_name: 'run_command', count: 1 }
          ])
        end
      end
    end

    context 'with external' do
      let(:agent_class) { :external }

      it 'keeps events from sessions with an agent type or a non-Duo source' do
        expect(tool_calls).to eq([
          { tool_name: 'Bash', count: 1 },
          { tool_name: 'Read', count: 1 }
        ])
      end
    end

    context 'when an event names a workflow and a session that disagree' do
      before do
        # workflow 1 has no agent type (internal), session 3 came from glab (external)
        insert_events([
          { id: 33, workflow_id: 1, session_id: 3, tool_name: 'Grep', created_at: '2026-07-03 13:00:00' }
        ])
      end

      it 'classifies through the session only, so the segments add up to all', :aggregate_failures do
        counts = %i[all internal_dap external].to_h do |segment|
          payload = described_class.new(container, current_user: user, timeframe: timeframe, agent_class: segment,
            sessions_enabled: true).execute.payload
          [segment, payload[:tool_calls]]
        end
        total = ->(rows) { rows.sum { |row| row[:count] } }

        expect(counts[:external]).to include({ tool_name: 'Grep', count: 1 })
        expect(counts[:internal_dap]).to eq([{ tool_name: 'create_issue', count: 1 }])
        expect(total.call(counts[:internal_dap]) + total.call(counts[:external])).to eq(total.call(counts[:all]))
      end
    end

    # The Compliance API ingest sets no workflow on Claude events, only a session.
    context 'with a Claude Code event that has a session but no workflow' do
      before do
        insert_events([
          { id: 34, workflow_id: 0, session_id: 3, event_name: 'ai_claude_tool_invoked', details: '{"name":"Glob"}',
            created_at: '2026-07-03 14:00:00' }
        ])
      end

      def tool_calls_for(segment, sessions:)
        described_class.new(container, current_user: user, timeframe: timeframe, agent_class: segment,
          sessions_enabled: sessions).execute.payload[:tool_calls]
      end

      it 'counts it as external when sessions are enabled', :aggregate_failures do
        expect(tool_calls_for(:external, sessions: true)).to include({ tool_name: 'Glob', count: 1 })
        expect(tool_calls_for(:internal_dap, sessions: true)).not_to include(a_hash_including(tool_name: 'Glob'))
      end

      it 'counts it as external when sessions are disabled too, since it has no workflow', :aggregate_failures do
        expect(tool_calls_for(:all, sessions: false)).to include({ tool_name: 'Glob', count: 1 })
        expect(tool_calls_for(:external, sessions: false)).to include({ tool_name: 'Glob', count: 1 })
        expect(tool_calls_for(:internal_dap, sessions: false)).to be_empty
      end
    end

    context 'when sessions are disabled' do
      let(:sessions_enabled) { false }

      it 'still counts the events for all' do
        expect(tool_calls.size).to eq(3)
      end

      context 'with internal_dap' do
        let(:agent_class) { :internal_dap }

        it 'drops session-backed events, since the workflow filter never sees them' do
          expect(tool_calls).to be_empty
        end
      end

      context 'with external' do
        let(:agent_class) { :external }

        # Without the flag every session-only event is external, even one from a Duo session.
        it 'keeps every session-backed event' do
          expect(tool_calls).to eq([
            { tool_name: 'Bash', count: 1 },
            { tool_name: 'Read', count: 1 },
            { tool_name: 'create_issue', count: 1 }
          ])
        end
      end
    end
  end

  def insert_workflows(rows)
    rows.each do |row|
      agent_type = row[:agent_type] ? "'#{row[:agent_type]}'" : 'NULL'

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_duo_workflows_workflows
          (id, user_id, created_at, workflow_definition, agent_type, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{user.id}, '#{workflow_created_at}', 'software_development', #{agent_type},
           '#{project_path}', '#{row.fetch(:replicated_at, workflow_created_at)}', #{row.fetch(:deleted, false)})
      SQL
    end
  end

  def insert_sessions(rows)
    rows.each do |row|
      agent_type = row[:agent_type] ? "'#{row[:agent_type]}'" : 'NULL'
      source = Ai::Governance::Session.sources.fetch(row[:source])

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_ai_governance_sessions
          (id, namespace_id, user_id, created_at, updated_at, session_started_at, source, agent_type,
           traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, #{project.project_namespace_id}, #{user.id}, '#{workflow_created_at}', '#{workflow_created_at}',
           '#{workflow_created_at}', #{source}, #{agent_type}, '#{project_path}', '#{workflow_created_at}', false)
      SQL
    end
  end

  def insert_events(rows)
    rows.each do |row|
      details = row[:details] || (row[:tool_name] ? %({"tool_name":"#{row[:tool_name]}"}) : '{}')

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO ai_audit_events
          (id, event_name, created_at, author_id, workflow_id, ai_governance_session_id, details, traversal_path)
        VALUES
          ('#{event_uuid(row[:id])}', '#{row.fetch(:event_name, 'ai_tool_invoked')}', '#{row[:created_at]}',
           #{user.id}, #{row.fetch(:workflow_id, 0)}, #{row.fetch(:session_id, 0)}, '#{details}',
           '#{row.fetch(:path, project_path)}')
      SQL
    end
  end

  def event_uuid(number)
    format('00000000-0000-0000-0000-%012d', number)
  end
end
