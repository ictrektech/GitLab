# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ClickHouseSessionDistributionService, :click_house,
  feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:timeframe) { Ai::Governance::MetricsTimeframe.new(:last_7_days) }
  let(:container) { group }
  let(:agent_class) { :all }
  let(:limit) { 10 }
  let(:group_path) { group.traversal_path(with_organization: true) }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    # Timeframe is 2026-06-26 00:00 (inclusive) to 2026-07-03 15:30 (exclusive).
    insert_rows([
      { id: 1, user: 1, flow_type: 'software_development/v1', started_at: '2026-06-26 00:00:00', path: project_path },
      { id: 2, user: 3, flow_type: 'software_development/v2', started_at: '2026-07-01 10:00:00', path: project_path },
      { id: 3, user: 1, flow_type: 'chat', started_at: '2026-07-01 11:00:00', path: group_path },
      { id: 4, user: 3, started_at: '2026-07-02 09:00:00', path: project_path },
      { id: 5, user: 1, source: 1, agent_type: 'claude-code', started_at: '2026-07-01 12:00:00', path: project_path },
      { id: 6, user: 2, source: 2, agent_type: 'claude-code', started_at: '2026-07-02 12:00:00', path: group_path },
      { id: 7, user: 3, source: 1, started_at: '2026-07-02 13:00:00', path: project_path },
      # glab workflow synced before !257427: Duo source, but external by agent_type
      { id: 8, user: 1, agent_type: 'claude-code', flow_type: 'external_agent', started_at: '2026-07-02 14:00:00',
        path: project_path },
      { id: 9, user: 2, source: 2, agent_type: 'opencode', started_at: '2026-07-02 15:00:00', path: project_path },
      # excluded: before the window, at its exclusive upper bound, outside the hierarchy
      { id: 10, user: 5, flow_type: 'chat', started_at: '2026-06-25 23:59:59', path: project_path },
      { id: 11, user: 5, flow_type: 'chat', started_at: '2026-07-03 15:30:00', path: project_path },
      { id: 12, user: 5, flow_type: 'chat', started_at: '2026-07-01 10:00:00', path: '0/999/' },
      # deleted in its latest version
      { id: 13, user: 4, flow_type: 'chat', started_at: '2026-07-01 10:00:00', path: project_path }
    ])
    # newer versions of existing rows: id 2 counts once for user 2, id 13 is gone
    insert_rows([
      { id: 2, user: 2, flow_type: 'software_development/v2', started_at: '2026-07-01 10:00:00', path: project_path,
        replicated_at: '2026-07-02 00:00:00' },
      { id: 13, user: 4, flow_type: 'chat', started_at: '2026-07-01 10:00:00', path: project_path,
        replicated_at: '2026-07-02 00:00:00', deleted: true }
    ])
  end

  subject(:distribution) do
    described_class.new(container, timeframe: timeframe, agent_class: agent_class, limit: limit).execute
  end

  it 'groups GitLab Duo sessions together and external sessions by agent type' do
    # user 1 is in two slices but counts once in the total
    expect(distribution).to eq(
      total_sessions: 9,
      total_developers: 3,
      slices: [
        { name: 'gitlab_duo', sessions: 4, developers: 3 },
        { name: 'claude-code', sessions: 3, developers: 2 },
        { name: 'opencode', sessions: 1, developers: 1 },
        { name: 'unknown', sessions: 1, developers: 1 }
      ]
    )
  end

  context 'with the INTERNAL_DAP agent class' do
    let(:agent_class) { :internal_dap }

    it 'counts GitLab Duo sessions only, by version-less flow type' do
      expect(distribution).to eq(
        total_sessions: 4,
        total_developers: 3,
        slices: [
          { name: 'software_development', sessions: 2, developers: 2 },
          { name: 'chat', sessions: 1, developers: 1 },
          { name: 'unknown', sessions: 1, developers: 1 }
        ]
      )
    end
  end

  context 'with the EXTERNAL agent class' do
    let(:agent_class) { :external }

    it 'counts external sessions only, by agent type' do
      expect(distribution).to eq(
        total_sessions: 5,
        total_developers: 3,
        slices: [
          { name: 'claude-code', sessions: 3, developers: 2 },
          { name: 'opencode', sessions: 1, developers: 1 },
          { name: 'unknown', sessions: 1, developers: 1 }
        ]
      )
    end
  end

  context 'with a limit' do
    let(:limit) { 2 }

    it 'returns the top slices and keeps the totals over every session' do
      expect(distribution).to eq(
        total_sessions: 9,
        total_developers: 3,
        slices: [
          { name: 'gitlab_duo', sessions: 4, developers: 3 },
          { name: 'claude-code', sessions: 3, developers: 2 }
        ]
      )
    end
  end

  context 'when the container is a project' do
    let(:container) { project }

    it 'counts only the sessions of that project' do
      expect(distribution).to eq(
        total_sessions: 7,
        total_developers: 3,
        slices: [
          { name: 'gitlab_duo', sessions: 3, developers: 3 },
          { name: 'claude-code', sessions: 2, developers: 1 },
          { name: 'opencode', sessions: 1, developers: 1 },
          { name: 'unknown', sessions: 1, developers: 1 }
        ]
      )
    end
  end

  context 'when there are no sessions in scope' do
    let(:container) { create(:group) }

    it 'returns zero totals and no slices' do
      expect(distribution).to eq(total_sessions: 0, total_developers: 0, slices: [])
    end
  end

  def insert_rows(rows)
    rows.each do |row|
      flow_type = row.key?(:flow_type) ? "'#{row[:flow_type]}'" : 'NULL'
      agent_type = row.key?(:agent_type) ? "'#{row[:agent_type]}'" : 'NULL'

      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO siphon_ai_governance_sessions
          (id, namespace_id, user_id, created_at, updated_at, session_started_at, source, flow_type, agent_type, traversal_path, _siphon_replicated_at, _siphon_deleted)
        VALUES
          (#{row[:id]}, 1, #{row[:user]}, '#{row[:started_at]}', '#{row[:started_at]}', '#{row[:started_at]}', #{row.fetch(:source, 0)}, #{flow_type}, #{agent_type},
           '#{row[:path]}', '#{row.fetch(:replicated_at, row[:started_at])}', #{row.fetch(:deleted, false)})
      SQL
    end
  end
end
