# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ToolCallsService, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:response) { ServiceResponse.success(payload: { tool_calls: [] }) }

  it 'counts Duo and Claude Code tool invocations' do
    expect(described_class::EVENTS).to contain_exactly('ai_tool_invoked', 'ai_claude_tool_invoked')
  end

  context 'when the container is a group' do
    subject(:execute) { described_class.new(group, current_user: user, timeframe: :last_7_days).execute }

    context 'when ClickHouse is enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(true)
      end

      it 'dispatches to the ClickHouse service and returns its tool calls', :aggregate_failures do
        expect_next_instance_of(Ai::Governance::ClickHouseToolCallsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute).to be_success
        expect(execute.payload).to eq(tool_calls: [], approximate: false)
      end
    end

    context 'when ClickHouse is not enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(false)
      end

      it 'returns an error without calling ClickHouse' do
        expect(Ai::Governance::ClickHouseToolCallsService).not_to receive(:new)

        expect(execute).to be_error
        expect(execute.message).to eq('ClickHouse is not enabled for analytics')
      end
    end
  end

  describe 'agent_class' do
    let(:backend) { Ai::Governance::ClickHouseToolCallsService }
    let(:backend_instance) { instance_double(backend, execute: response) }

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).with(group).and_return(true)
    end

    it 'defaults to :all' do
      expect(backend).to receive(:new).with(group, hash_including(agent_class: :all))
        .and_return(backend_instance)

      described_class.new(group, current_user: user, timeframe: :last_7_days).execute
    end

    %i[all internal_dap external].each do |agent_class|
      it "passes #{agent_class} through to the backend" do
        expect(backend).to receive(:new).with(group, hash_including(agent_class: agent_class))
          .and_return(backend_instance)

        described_class.new(group, current_user: user, timeframe: :last_7_days, agent_class: agent_class).execute
      end
    end
  end

  describe 'sessions_enabled' do
    let(:backend) { Ai::Governance::ClickHouseToolCallsService }
    let(:backend_instance) { instance_double(backend, execute: response) }

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
    end

    it 'follows the ai_governance_sessions_api flag on the root ancestor' do
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

  context 'when the container is a project' do
    subject(:execute) { described_class.new(project, current_user: user, timeframe: :last_7_days).execute }

    context 'when ClickHouse is enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?)
          .with(project.project_namespace).and_return(true)
      end

      it 'dispatches to the ClickHouse service' do
        expect_next_instance_of(Ai::Governance::ClickHouseToolCallsService) do |service|
          expect(service).to receive(:execute).and_return(response)
        end

        expect(execute.payload).to eq(tool_calls: [], approximate: false)
      end
    end

    context 'when ClickHouse is not enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?)
          .with(project.project_namespace).and_return(false)
      end

      it 'returns an error without calling ClickHouse' do
        expect(Ai::Governance::ClickHouseToolCallsService).not_to receive(:new)

        expect(execute).to be_error
        expect(execute.message).to eq('ClickHouse is not enabled for analytics')
      end
    end
  end

  describe 'grouping by the rule that governs each tool' do
    let(:backend) { Ai::Governance::ClickHouseToolCallsService }
    let(:recorded) { [] }
    let(:mcp_tools) do
      Ai::ToolRules::GovernedMcpTools.new(
        'get_repository_file' => { identities: ['get_repository_file'], action_type: :read },
        'list_repository_tree' => { identities: ['list_repository_tree'], action_type: :read }
      )
    end

    subject(:payload) { described_class.new(group, current_user: user, timeframe: :last_7_days).execute.payload }

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
      allow(Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).and_return(mcp_tools)
      allow(backend).to receive(:new).and_return(
        instance_double(backend,
          execute: ServiceResponse.success(payload: { tool_calls: recorded, approximate: false }))
      )
    end

    def recorded_call(tool_name, count)
      { tool_name: tool_name, count: count }
    end

    context 'with the same tool recorded under two spellings' do
      let(:recorded) do
        [
          recorded_call('orbit_invoke_command', 11),
          recorded_call('get_repository_file', 4),
          recorded_call('gitlab_get_repository_file', 1),
          recorded_call('gitlab_list_repository_tree', 1),
          recorded_call('list_repository_tree', 1)
        ]
      end

      it 'sums them into one row under the rule that governs them', :aggregate_failures do
        expect(payload[:tool_calls]).to eq([
          { tool_name: 'orbit_invoke_command', governed: false, action_type: nil, count: 11 },
          { tool_name: 'get_repository_file', governed: true, action_type: :read, count: 5 },
          { tool_name: 'list_repository_tree', governed: true, action_type: :read, count: 2 }
        ])
        expect(payload[:approximate]).to be(false)
      end

      it 'keeps the total the card shows equal to the recorded calls' do
        expect(payload[:tool_calls].sum { |row| row[:count] }).to eq(recorded.sum { |call| call[:count] })
      end
    end

    context 'when grouping changes which tools make the top ten' do
      let(:recorded) do
        Array.new(10) { |i| recorded_call(format('tool_%02d', i), 2) } +
          [recorded_call('get_repository_file', 1), recorded_call('gitlab_get_repository_file', 2)]
      end

      it 'groups before cutting to the top ten', :aggregate_failures do
        expect(payload[:tool_calls].size).to eq(described_class::TOP_N)
        expect(payload[:tool_calls].first).to include(tool_name: 'get_repository_file', count: 3)
      end
    end

    context 'when the namespace recorded more distinct names than the cap' do
      let(:recorded) { [recorded_call('tool_a', 3), recorded_call('tool_b', 2), recorded_call('tool_c', 1)] }

      before do
        stub_const("#{described_class}::TOOL_NAME_LIMIT", 2)
      end

      it 'groups only the most called names and flags the result approximate', :aggregate_failures do
        expect(payload[:tool_calls].pluck(:tool_name)).to eq(%w[tool_a tool_b])
        expect(payload[:approximate]).to be(true)
      end
    end

    it 'asks the ClickHouse service for every recorded name, not just the top ten' do
      described_class.new(group, current_user: user, timeframe: :last_7_days).execute

      expect(backend).to have_received(:new).with(group, hash_including(limit: described_class::TOOL_NAME_LIMIT + 1))
    end
  end

  context 'when the ClickHouse tool calls service fails' do
    let(:error) { ServiceResponse.error(message: 'boom') }

    before do
      allow(::Gitlab::ClickHouse).to receive(:enabled_for_analytics?).and_return(true)
      allow_next_instance_of(Ai::Governance::ClickHouseToolCallsService) do |service|
        allow(service).to receive(:execute).and_return(error)
      end
    end

    it 'returns that error response' do
      expect(described_class.new(group, current_user: user, timeframe: :last_7_days).execute).to eq(error)
    end
  end
end
