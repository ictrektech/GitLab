# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::SessionPolicyService, feature_category: :duo_agent_platform do
  describe '#execute' do
    subject(:policies) do
      described_class.new(container: container, environment: environment, workflow_definition: 'chat').execute
    end

    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    let(:container) { project }
    let(:environment) { 'web' }

    before_all do
      create(:ai_tool_rule, namespace: group, tool_name: 'run_command', web_access: :ask)
      create(:ai_tool_rule, namespace: group, project: project, tool_name: 'create_merge_request', web_access: :deny)
    end

    it 'resolves the group and project rules for the session surface' do
      expect(policies[:ask_tools]).to include('run_command')
      expect(policies[:denied_tools]).to include('create_merge_request')
    end

    context 'when the container is a group' do
      let(:container) { group }

      it 'leaves out project rules' do
        expect(policies[:ask_tools]).to include('run_command')
        expect(policies[:denied_tools]).not_to include('create_merge_request')
      end
    end

    context 'when there is no container' do
      let(:container) { nil }

      it { is_expected.to eq(described_class::EMPTY_TOOL_POLICIES) }
    end

    context 'when the session runs on a surface that is not governed' do
      let(:environment) { 'ide' }

      before do
        stub_feature_flags(duo_workflow_local_tool_governance: false)
      end

      it 'returns empty policies without resolving rules' do
        expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

        expect(policies).to eq(described_class::EMPTY_TOOL_POLICIES)
      end
    end

    context 'when resolution fails' do
      before do
        allow_next_instance_of(Ai::ToolRules::ResolutionService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
        end
      end

      it { is_expected.to eq(described_class::EMPTY_TOOL_POLICIES) }
    end
  end
end
