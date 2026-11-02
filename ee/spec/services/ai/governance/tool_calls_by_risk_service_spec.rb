# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ToolCallsByRiskService, :click_house, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  let(:workflow_created_at) { '2026-01-15 09:00:00' }
  let(:agent_class) { :all }
  let(:container) { group }
  let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }
  let(:result) do
    described_class.new(container, current_user: user, timeframe: :last_7_days, agent_class: agent_class).execute
  end

  subject(:payload) { result.payload }

  around do |example|
    travel_to(Time.utc(2026, 7, 3, 15, 30)) { example.run }
  end

  before do
    allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)

    insert_workflows([
      { id: 1 },
      { id: 2, agent_type: 'claude_code' }
    ])

    # get_issue is a read, create_issue a write, run_command a destroy in Ai::ToolRules::Registry
    insert_events([
      { id: 1, workflow_id: 1, tool_name: 'get_issue' },
      { id: 2, workflow_id: 1, tool_name: 'get_issue' },
      { id: 3, workflow_id: 1, tool_name: 'create_issue' },
      { id: 4, workflow_id: 2, tool_name: 'run_command' },
      { id: 5, workflow_id: 2, tool_name: 'not_a_registered_tool' },
      { id: 6, workflow_id: 2, tool_name: 'get_issue' }
    ])
  end

  it 'counts the tool calls per risk level in a fixed order', :aggregate_failures do
    expect(result).to be_success
    expect(payload).to eq(
      total: 6,
      slices: [
        { risk: :read, count: 3 },
        { risk: :write, count: 1 },
        { risk: :destroy, count: 1 },
        { risk: :unclassified, count: 1 }
      ],
      approximate: false
    )
  end

  it 'asks the ClickHouse service for every tool name, not just the top N' do
    expect(Ai::Governance::ClickHouseToolCallsService).to receive(:new)
      .with(group, hash_including(limit: described_class::TOOL_NAME_LIMIT + 1))
      .and_call_original

    result
  end

  describe 'sessions_enabled' do
    let(:backend) { Ai::Governance::ClickHouseToolCallsService }
    let(:backend_instance) do
      instance_double(backend, execute: ServiceResponse.success(payload: { tool_calls: [], approximate: false }))
    end

    it 'follows the ai_governance_sessions_api flag on the root ancestor, like the top tools card' do
      stub_feature_flags(ai_governance_sessions_api: group)

      expect(backend).to receive(:new).with(project, hash_including(sessions_enabled: true))
        .and_return(backend_instance)

      described_class.new(project, current_user: user, timeframe: :last_7_days).execute
    end

    it 'is false when the flag is disabled' do
      stub_feature_flags(ai_governance_sessions_api: false)

      expect(backend).to receive(:new).with(group, hash_including(sessions_enabled: false))
        .and_return(backend_instance)

      described_class.new(group, current_user: user, timeframe: :last_7_days).execute
    end
  end

  context 'when the namespace used more distinct tools than the cap' do
    before do
      stub_const("#{described_class}::TOOL_NAME_LIMIT", 2)
    end

    it 'counts only the most called tools and flags the result approximate', :aggregate_failures do
      expect(payload[:approximate]).to be(true)
      expect(payload[:total]).to eq(4)
      expect(payload[:slices]).to eq([
        { risk: :read, count: 3 },
        { risk: :write, count: 1 },
        { risk: :destroy, count: 0 },
        { risk: :unclassified, count: 0 }
      ])
    end
  end

  context 'with a project container' do
    let(:container) { project }

    it 'classifies MCP tools against the root namespace, like the Tool management tab', :aggregate_failures do
      expect(::Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).and_call_original

      expect(payload[:total]).to eq(6)
    end
  end

  context 'with a tool the MCP server serves' do
    let(:mcp_tools) do
      ::Ai::ToolRules::GovernedMcpTools.new(
        'acme_mcp_deploy' => { identities: ['acme_mcp_deploy'], action_type: :destroy }
      )
    end

    before do
      allow(::Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).and_return(mcp_tools)
      # The Duo Workflow Service records MCP tools under their prefixed name.
      insert_events([
        { id: 7, workflow_id: 1, tool_name: 'gitlab_acme_mcp_deploy' },
        { id: 8, workflow_id: 1, tool_name: 'gitlab_not_served' }
      ])
    end

    it 'takes the risk from the MCP tool hints and leaves unknown prefixed names unclassified',
      :aggregate_failures do
      expect(payload[:total]).to eq(8)
      expect(payload[:slices]).to include({ risk: :destroy, count: 2 })
      expect(payload[:slices]).to include({ risk: :unclassified, count: 2 })
    end
  end

  context 'with GitLab MCP tools governed through the catalog' do
    let(:mcp_tools) do
      ::Ai::ToolRules::GovernedMcpTools.new(
        # The MCP annotation says write, the governing catalog rule says read: the rule wins.
        'list_merge_requests' => { identities: ['gitlab_merge_request_search'], action_type: :write },
        'save_work_item' => { identities: %w[create_work_item update_work_item], action_type: :write }
      )
    end

    before do
      allow(::Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).and_return(mcp_tools)
      insert_events([
        { id: 7, workflow_id: 1, tool_name: 'gitlab_list_merge_requests' },
        { id: 8, workflow_id: 1, tool_name: 'gitlab_save_work_item' }
      ])
    end

    it 'classifies an aliased tool by the rule that governs it, like the Top tools card badge',
      :aggregate_failures do
      expect(payload[:total]).to eq(8)
      expect(payload[:slices]).to include({ risk: :read, count: 4 })
    end

    it 'falls back to the declared action type for a tool several rules govern' do
      expect(payload[:slices]).to include({ risk: :write, count: 2 })
    end
  end

  context 'with agent_class internal_dap' do
    let(:agent_class) { :internal_dap }

    it 'passes the filter through and keeps the empty risk levels at zero' do
      expect(payload).to eq(
        total: 3,
        slices: [
          { risk: :read, count: 2 },
          { risk: :write, count: 1 },
          { risk: :destroy, count: 0 },
          { risk: :unclassified, count: 0 }
        ],
        approximate: false
      )
    end
  end

  context 'when no tools were called in the namespace' do
    let(:container) { create(:group) }

    it 'returns every risk level with a zero count' do
      expect(payload).to eq(
        total: 0,
        slices: %i[read write destroy unclassified].map { |risk| { risk: risk, count: 0 } },
        approximate: false
      )
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(false)
    end

    it 'returns an error without querying ClickHouse', :aggregate_failures do
      expect(Ai::Governance::ClickHouseToolCallsService).not_to receive(:new)

      expect(result).to be_error
      expect(result.message).to eq('ClickHouse is not enabled for analytics')
    end
  end

  context 'when the ClickHouse tool calls service fails' do
    let(:error) { ServiceResponse.error(message: 'boom') }

    before do
      allow_next_instance_of(Ai::Governance::ClickHouseToolCallsService) do |service|
        allow(service).to receive(:execute).and_return(error)
      end
    end

    it 'returns that error response', :aggregate_failures do
      expect(result).to be_error
      expect(result.message).to eq('boom')
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
           '#{project_path}', '#{workflow_created_at}', false)
      SQL
    end
  end

  def insert_events(rows)
    rows.each do |row|
      ClickHouse::Client.execute(<<~SQL, :main)
        INSERT INTO ai_audit_events
          (id, event_name, created_at, author_id, workflow_id, details, traversal_path)
        VALUES
          ('#{event_uuid(row[:id])}', 'ai_tool_invoked', '2026-07-01 10:00:00',
           #{user.id}, #{row[:workflow_id]}, '{"tool_name":"#{row[:tool_name]}"}', '#{project_path}')
      SQL
    end
  end

  def event_uuid(number)
    format('00000000-0000-0000-0000-%012d', number)
  end
end
