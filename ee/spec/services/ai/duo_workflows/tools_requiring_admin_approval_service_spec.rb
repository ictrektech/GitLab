# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::ToolsRequiringAdminApprovalService, feature_category: :duo_agent_platform do
  describe '#execute' do
    subject(:tool_names) { described_class.new(workflow: workflow).execute }

    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:user) { create(:user, maintainer_of: project) }

    let(:workflow) { create(:duo_workflows_workflow, project: project, user: user, environment: :web) }

    it 'returns nothing when no rule applies' do
      expect(tool_names).to be_empty
    end

    it 'returns the tools an admin set to Ask or Deny' do
      create(:ai_tool_rule, namespace: group, tool_name: 'run_command', web_access: :ask)
      create(:ai_tool_rule, namespace: group, tool_name: 'create_merge_request', web_access: :deny)
      create(:ai_tool_rule, namespace: group, tool_name: 'read_file', web_access: :allow)

      # A deny also covers the GitLab MCP spelling of the tool.
      expect(tool_names).to contain_exactly('run_command', 'create_merge_request', 'gitlab_save_merge_request')
    end

    it 'includes a project rule on the workflow project' do
      create(:ai_tool_rule, namespace: group, project: project, tool_name: 'run_command', web_access: :ask)

      expect(tool_names).to contain_exactly('run_command')
    end

    context 'when the workflow runs on a surface that is not governed' do
      let(:workflow) { create(:duo_workflows_workflow, project: project, user: user, environment: :ide) }

      before do
        create(:ai_tool_rule, namespace: group, tool_name: 'run_command', web_access: :ask, local_access: :ask)
        stub_feature_flags(duo_workflow_local_tool_governance: false)
      end

      it 'returns nothing' do
        expect(tool_names).to be_empty
      end
    end

    context 'when the workflow has no project or namespace' do
      before do
        allow(workflow).to receive(:resource_parent).and_return(nil)
      end

      it 'returns nothing' do
        expect(tool_names).to be_empty
      end
    end

    context 'when resolution fails' do
      before do
        allow_next_instance_of(::Ai::ToolRules::ResolutionService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
        end
      end

      it 'returns nothing' do
        expect(tool_names).to be_empty
      end
    end
  end
end
