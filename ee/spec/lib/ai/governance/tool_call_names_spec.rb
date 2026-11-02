# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::ToolCallNames, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: create(:group, parent: group)) }

  let(:mcp_tools) do
    Ai::ToolRules::GovernedMcpTools.new(
      'get_repository_file' => { identities: ['get_repository_file'], action_type: :read },
      # The MCP annotation differs from the governing rule on purpose: the rule wins.
      'list_merge_requests' => { identities: ['gitlab_merge_request_search'], action_type: :write },
      'save_work_item' => { identities: %w[create_work_item update_work_item], action_type: :write }
    )
  end

  subject(:names) { described_class.new(project) }

  before do
    allow(Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).and_return(mcp_tools)
  end

  it 'names a built-in tool by its rule, as the Tool management tab does' do
    expect(names.resolve('create_issue')).to eq(tool_name: 'create_issue', governed: true, action_type: :write)
  end

  it 'names a GitLab MCP spelling by the rule that governs it' do
    expect(names.resolve('gitlab_get_repository_file'))
      .to eq(tool_name: 'get_repository_file', governed: true, action_type: :read)
  end

  it 'takes the action type from the governing rule for an aliased MCP tool' do
    expect(names.resolve('gitlab_list_merge_requests'))
      .to eq(tool_name: 'gitlab_merge_request_search', governed: true, action_type: :read)
  end

  it 'keeps the recorded name and the declared action type for a tool several rules govern' do
    expect(names.resolve('gitlab_save_work_item'))
      .to eq(tool_name: 'gitlab_save_work_item', governed: false, action_type: :write)
  end

  it 'keeps the recorded name with no action type when nothing governs it' do
    expect(names.resolve('orbit_invoke_command'))
      .to eq(tool_name: 'orbit_invoke_command', governed: false, action_type: nil)
  end

  it 'looks up the MCP catalog of the root namespace once' do
    expect(Ai::ToolRules::GovernedMcpTools).to receive(:for).with(group).once.and_return(mcp_tools)

    names.resolve('gitlab_get_repository_file')
    names.resolve('create_issue')
  end
end
