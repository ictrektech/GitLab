# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Mcp::Handlers::ListTools, feature_category: :mcp_server do
  let(:manager) { instance_double(Mcp::Tools::Manager) }
  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }

  let(:tool_name) { 'get_work_item_types' }

  let(:tool) { stubbed_tool }

  subject(:handler) { described_class.new(manager) }

  def stubbed_tool
    instance_double(
      Mcp::Tools::Base::BaseService,
      description: 'Test tool',
      input_schema: { type: 'object' },
      unlisted?: false,
      available?: true,
      toolset: :work_items
    ).tap do |double|
      allow(double).to receive(:is_a?).with(Mcp::Tools::Base::BaseService).and_return(true)
      allow(double).to receive(:is_a?).with(Mcp::Tools::Base::CustomService).and_return(false)
      allow(double).to receive(:try).with(:icons).and_return(nil)
      allow(double).to receive(:try).with(:annotations).and_return(nil)
    end
  end

  before do
    allow(manager).to receive(:list_tools).and_return({ tool_name => tool })

    allow(current_user).to receive(:governing_namespace).and_return(group)
    stub_feature_flags(duo_mcp_server_governance_rule_enforcement: group)
  end

  def listed
    handler.invoke(current_user)[:tools]
  end

  describe '#invoke' do
    context 'when the tool is denied' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
      end

      it 'omits it from the advertised toolset' do
        expect(listed).to be_empty
      end

      context 'when the flag is disabled' do
        before do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
        end

        it 'advertises it again' do
          expect(listed.pluck(:name)).to contain_exactly(tool_name)
        end
      end

      context 'when another tool carries no rule' do
        let(:allowed_tool_name) { 'get_issue' }

        before do
          allow(manager).to receive(:list_tools)
            .and_return({ tool_name => tool, allowed_tool_name => stubbed_tool })
        end

        it 'omits the denied tool and keeps the other' do
          expect(listed.pluck(:name)).to contain_exactly(allowed_tool_name)
        end
      end
    end

    context 'when only a project in the namespace denies the tool' do
      let_it_be(:project) { create(:project, group: group) }

      before do
        create(:ai_tool_rule, namespace: group, project: project, tool_name: tool_name, local_access: :deny)
      end

      it 'still advertises it, because the list reads only the namespace rules' do
        expect(listed.pluck(:name)).to contain_exactly(tool_name)
      end
    end

    context 'when the tool resolves to ask' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :ask)
      end

      it 'advertises it with the interaction annotation' do
        expect(listed.first[:_meta]).to eq(
          { 'com.gitlab/toolset' => 'work_items', 'anthropic/requiresUserInteraction' => true }
        )
      end
    end

    context 'when a write tool has no rule' do
      let(:tool_name) { 'create_issue' }

      it 'advertises it unannotated, although its default is ask' do
        expect(Ai::ToolRules::McpGovernance.new(group, include_projects: false).permission_for(tool_name)).to eq('ask')
        expect(listed.first[:_meta]).to eq({ 'com.gitlab/toolset' => 'work_items' })
      end
    end

    context 'when the tool resolves to allow' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :allow)
      end

      it 'advertises it unannotated' do
        expect(listed.first[:_meta]).to eq({ 'com.gitlab/toolset' => 'work_items' })
      end
    end

    context 'when the caller has no namespace to govern against' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
      end

      it 'returns a response identical to the one with governance off' do
        allow(current_user).to receive(:governing_namespace).and_return(nil)

        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
        ungoverned = described_class.new(manager).invoke(current_user)

        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: group)

        expect(described_class.new(manager).invoke(current_user)).to eq(ungoverned)
      end

      it 'attaches no interaction annotation' do
        allow(current_user).to receive(:governing_namespace).and_return(nil)

        expect(listed.pluck(:_meta)).to all(exclude('anthropic/requiresUserInteraction'))
      end
    end

    context 'when a rule exists for another surface only' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, web_access: :deny)
      end

      it 'leaves the tool on its default rather than applying the web rule' do
        expect(listed.pluck(:name)).to contain_exactly(tool_name)
      end
    end
  end

  describe '#invoke for an anonymous caller' do
    before do
      create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
    end

    it 'advertises the tool, because there is no namespace to govern against' do
      expect(handler.invoke(nil)[:tools].pluck(:name)).to contain_exactly(tool_name)
    end
  end
end
