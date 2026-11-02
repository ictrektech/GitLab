# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ClickHouseConnectedAgentActivityService, :click_house,
  feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }
  let(:agent_types) { %w[claude-code opencode] }
  let(:group_path) { group.traversal_path(with_organization: true) }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    # Timeframe is 2026-06-26 00:00 (inclusive) to 2026-07-03 15:30 (exclusive).
    insert_rows([
      { id: 1, agent_type: 'claude-code', started_at: '2026-07-01 10:00:00', path: project_path },
      { id: 2, source: 1, agent_type: 'claude-code', started_at: '2026-07-02 10:00:00', path: group_path },
      # before the window: last_session_at only
      { id: 3, agent_type: 'opencode', started_at: '2026-06-20 09:00:00', path: project_path },
      # excluded: Duo source, no identity, unrequested agent type, outside the hierarchy, deleted
      { id: 4, source: 0, agent_type: 'claude-code', started_at: '2026-07-02 11:00:00', path: project_path },
      { id: 5, agent_type: 'claude-code', identity: 'NULL', started_at: '2026-07-02 12:00:00', path: project_path },
      { id: 6, agent_type: 'codex', started_at: '2026-07-02 13:00:00', path: project_path },
      { id: 7, agent_type: 'claude-code', started_at: '2026-07-03 09:00:00', path: '0/999/' },
      { id: 8, agent_type: 'claude-code', started_at: '2026-07-03 10:00:00', path: project_path }
    ])
    # newer versions: id 1 must count once, id 8 is gone
    insert_rows([
      { id: 1, agent_type: 'claude-code', started_at: '2026-07-01 10:00:00', path: project_path,
        replicated_at: '2026-07-03 00:00:00' },
      { id: 8, agent_type: 'claude-code', started_at: '2026-07-03 10:00:00', path: project_path,
        replicated_at: '2026-07-03 11:00:00', deleted: true }
    ])
  end

  def execute(container)
    described_class.new(container, timeframe: timeframe, agent_types: agent_types).execute
  end

  it 'returns external session counts in the window and the last session per agent type' do
    expect(execute(group)).to eq(
      'claude-code' => [2, Time.utc(2026, 7, 2, 10)],
      'opencode' => [0, Time.utc(2026, 6, 20, 9)]
    )
  end

  it 'scopes a project container to that project' do
    expect(execute(project)).to eq(
      'claude-code' => [1, Time.utc(2026, 7, 1, 10)],
      'opencode' => [0, Time.utc(2026, 6, 20, 9)]
    )
  end

  def insert_rows(rows)
    rows.each do |row|
      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_ai_governance_sessions
          (id, namespace_id, user_id, created_at, updated_at, session_started_at, source, agent_type, agent_identity_id, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, 1, 1, '#{row[:started_at]}', '#{row[:started_at]}', '#{row[:started_at]}', #{row.fetch(:source, 2)}, '#{row[:agent_type]}', #{row.fetch(:identity, 501)},
           '#{row[:path]}', '#{row.fetch(:replicated_at, row[:started_at])}', #{row.fetch(:deleted, false)})
      SQL
    end
  end
end
