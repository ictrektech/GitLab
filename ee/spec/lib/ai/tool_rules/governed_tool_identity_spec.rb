# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP tools honour the rule stored under their governing name', feature_category: :ai_agents do
  let_it_be(:namespace) { create(:group) }

  let(:manager) { ::Mcp::Tools::Manager.new }
  let(:governed_tools) { ::Ai::ToolRules::GovernedMcpTools.for(namespace) }

  let(:mapped_tools) do
    governed_tools.names.reject { |name| governed_tools.identities_for(name) == [name] }
  end

  before do
    stub_feature_flags(duo_mcp_tool_governance: namespace, duo_mcp_server_governance_rule_enforcement: namespace)
  end

  def permission_for(spelling)
    ::Ai::ToolRules::McpGovernance
      .new([namespace])
      .permission_for(manager.resolve_alias(spelling))
  end

  it 'has mappings to check' do
    expect(mapped_tools).not_to be_empty
  end

  it 'governs get_issue and get_work_item by either name', :aggregate_failures do
    %w[get_issue get_work_item].each do |governing_name|
      rule = create(:ai_tool_rule, namespace: namespace, tool_name: governing_name, local_access: :deny)

      expect(permission_for('get_issue')).to eq(::Ai::ToolRules::Permissions::DENY),
        "`get_issue` ignored the deny rule stored as `#{governing_name}`"
      expect(permission_for('get_work_item')).to eq(::Ai::ToolRules::Permissions::DENY),
        "`get_work_item` ignored the deny rule stored as `#{governing_name}`"

      rule.destroy!
    end
  end

  it 'keeps the replacement-tool link off the Duo Agent Platform spellings' do
    prefix = ::Ai::DuoWorkflows::McpConfigService::MCP_SERVER_TOOL_PREFIX

    expect(governed_tools.spellings_for('get_issue')).not_to include("#{prefix}get_work_item")
  end

  it 'maps only retired tools in the name exception list' do
    still_listed = ::Ai::ToolRules::Registry::REPLACEMENT_TOOL_FOR.keys.select do |name|
      tool = manager.list_tools[name]
      tool && !tool.unlisted?
    end

    expect(still_listed).to be_empty,
      "REPLACEMENT_TOOL_FOR is a retirement map, so every key has " \
        "to be a tool that is unlisted pending removal. These are still listed, and mapping them " \
        "makes each govern the other's rules: #{still_listed.join(', ')}"
  end

  it 'maps every tool unlisted for removal to a replacement' do
    superseded_by_a_facet = %w[
      get_workitem_notes get_merge_request_conflicts get_merge_request_commits
      get_merge_request_pipelines get_pipeline_jobs
    ].freeze
    governed_under_own_name = %w[manage_pipeline create_issue].freeze

    unmapped = governed_tools.names.select do |name|
      tool = manager.list_tools[name]
      next false unless tool&.unlisted?
      next false if superseded_by_a_facet.include?(name)
      next false if governed_under_own_name.include?(name)

      governed_tools.identities_for(name) == [name]
    end

    expect(unmapped).to be_empty,
      "these tools are unlisted but carry no replacement in Registry::REPLACEMENT_TOOL_FOR, " \
        "so a rule set under either name stops applying: #{unmapped.join(', ')}"
  end

  it 'enforces a deny stored under the governing name', :aggregate_failures do
    mapped_tools.each do |served|
      governed_tools.identities_for(served).each do |governing_name|
        rule = create(:ai_tool_rule, namespace: namespace, tool_name: governing_name, local_access: :deny)

        expect(permission_for(served)).to eq(::Ai::ToolRules::Permissions::DENY),
          "`#{served}` ignored the deny rule stored as `#{governing_name}`"
        expect(permission_for(governing_name)).to eq(::Ai::ToolRules::Permissions::DENY),
          "`#{governing_name}` did not resolve to its own deny rule"

        rule.destroy!
      end
    end
  end
end
