# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ToolRules::McpGovernance, feature_category: :ai_agents do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:project) { create(:project, group: namespace) }

  subject(:governance) { described_class.new([namespace]) }

  describe '#permission_for' do
    context 'when the flag is enabled' do
      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace)
      end

      it 'reads the local_access column, matching an editor extension' do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue',
          local_access: :deny, web_access: :allow)

        expect(governance.permission_for('create_issue')).to eq('deny')
      end

      it 'falls back to the registry default when no rule exists' do
        expect(governance.permission_for('create_issue'))
          .to eq(::Ai::ToolRules::Registry.default_permission_of('create_issue'))
      end

      it 'applies the rules of the namespace it is given, with no caller involved' do
        other = create(:group)
        create(:ai_tool_rule, namespace: other, tool_name: 'create_issue', local_access: :deny)
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: other)

        expect(described_class.new([other]).permission_for('create_issue')).to eq('deny')
      end

      it 'climbs a subgroup to the root namespace its rules are stored against' do
        subgroup = create(:group, parent: namespace)
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :deny)

        expect(described_class.new([subgroup]).permission_for('create_issue')).to eq('deny')
      end

      it 'lets a project rule override an allow on its group' do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :allow)
        create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue',
          local_access: :deny)

        expect(described_class.new([project]).permission_for('create_issue')).to eq('deny')
      end

      it 'still reads group rules when given a project with none of its own' do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :deny)

        expect(described_class.new([project]).permission_for('create_issue')).to eq('deny')
      end

      it 'takes the most restrictive verdict across every container named' do
        allowing = create(:group)
        denying = create(:group)
        create(:ai_tool_rule, namespace: allowing, tool_name: 'create_issue', local_access: :allow)
        create(:ai_tool_rule, namespace: denying, tool_name: 'create_issue', local_access: :deny)
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: true)

        expect(described_class.new([allowing, denying]).permission_for('create_issue')).to eq('deny')
      end

      it 'is unaffected by the order the containers are named in' do
        allowing = create(:group)
        denying = create(:group)
        create(:ai_tool_rule, namespace: allowing, tool_name: 'create_issue', local_access: :allow)
        create(:ai_tool_rule, namespace: denying, tool_name: 'create_issue', local_access: :deny)
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: true)

        expect(described_class.new([denying, allowing]).permission_for('create_issue')).to eq('deny')
      end

      it 'reuses one resolution service across lookups' do
        expect(::Ai::ToolRules::ResolutionService).to receive(:new).once.and_call_original

        3.times { governance.permission_for('create_issue') }
      end

      context 'with several containers under one namespace' do
        let_it_be(:subgroups) { create_list(:group, 3, parent: namespace) }
        let_it_be(:projects) { create_list(:project, 3, group: namespace) }

        before do
          create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :deny)
        end

        it 'reads the namespace rules once for sibling subgroups' do
          expect { described_class.new(subgroups).permission_for('create_issue') }
            .to issue_same_number_of_queries_as {
              described_class.new(subgroups.first(1)).permission_for('create_issue')
            }
        end

        it 'reads the namespace rules once for sibling projects' do
          expect { described_class.new(projects).permission_for('create_issue') }
            .not_to exceed_query_limit(4)
        end

        it 'reads the project rules once for a group with several ruled projects' do
          create(:ai_tool_rule, namespace: namespace, project: projects.first, tool_name: 'create_issue',
            local_access: :deny)

          control = ActiveRecord::QueryRecorder.new do
            described_class.new([namespace]).permission_for('create_issue')
          end

          projects.drop(1).each do |project|
            create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue',
              local_access: :deny)
          end

          expect { described_class.new([namespace]).permission_for('create_issue') }
            .not_to exceed_query_limit(control)
        end
      end
    end

    context 'when governance cannot apply' do
      before do
        create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :deny)
      end

      context 'without a namespace' do
        it 'returns nil without touching the rules' do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace)

          expect(::Ai::ToolRules::ResolutionService).not_to receive(:new)

          expect(described_class.new([]).permission_for('create_issue')).to be_nil
        end
      end

      context 'when the flag is disabled' do
        it 'returns nil even where a deny rule exists' do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)

          expect(governance.permission_for('create_issue')).to be_nil
        end
      end

      context 'when local tool governance is disabled for the namespace' do
        it 'returns nil even where a deny rule exists' do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace,
            duo_workflow_local_tool_governance: false)

          expect(governance.permission_for('create_issue')).to be_nil
        end
      end
    end
  end

  describe 'loading rules' do
    let_it_be(:other_project) { create(:project, group: namespace) }

    before do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace)
      create(:ai_tool_rule, namespace: namespace, project: other_project, tool_name: 'create_issue',
        local_access: :deny)
    end

    it 'loads only the rules of the named project when no group is named' do
      expect(::Ai::ToolRule).not_to receive(:within_namespace)

      expect(described_class.new([project]).permission_for('create_issue')).not_to eq('deny')
    end

    it 'loads every project rule when a group is named' do
      expect(described_class.new([namespace]).permission_for('create_issue')).to eq('deny')
    end

    it 'leaves project rules out when asked for the namespace alone' do
      expect(described_class.new([namespace], include_projects: false).permission_for('create_issue'))
        .not_to eq('deny')
    end
  end

  describe '.enabled_anywhere?' do
    it 'is true when both flags are enabled for some actor' do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace,
        duo_workflow_local_tool_governance: namespace)

      expect(described_class.enabled_anywhere?).to be(true)
    end

    it 'is false when the enforcement flag is off for every actor' do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)

      expect(described_class.enabled_anywhere?).to be(false)
    end

    it 'is false when local tool governance is off for every actor' do
      stub_feature_flags(duo_workflow_local_tool_governance: false)

      expect(described_class.enabled_anywhere?).to be(false)
    end
  end

  describe '#explicit_permission_for' do
    before do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace)
    end

    it 'is nil when no rule exists, even though the default is ask' do
      expect(governance.permission_for('create_issue')).to eq('ask')
      expect(governance.explicit_permission_for('create_issue')).to be_nil
    end

    it 'returns the permission a rule sets' do
      create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :ask)

      expect(governance.explicit_permission_for('create_issue')).to eq('ask')
    end

    it 'takes the most restrictive rule across a group and its ruled projects' do
      create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :allow)
      create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', local_access: :ask)

      expect(governance.explicit_permission_for('create_issue')).to eq('ask')
    end
  end

  describe '#denied_by' do
    before do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace)
    end

    it 'returns the project whose rule denies the tool' do
      create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', local_access: :deny)

      expect(described_class.new([project]).denied_by('create_issue')).to eq(project)
    end

    it 'returns the group whose rule denies the tool' do
      create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :deny)

      expect(governance.denied_by('create_issue')).to eq(namespace)
    end

    it 'returns a ruled project under the named group when only the project denies the tool' do
      create(:ai_tool_rule, namespace: namespace, project: project, tool_name: 'create_issue', local_access: :deny)

      expect(governance.denied_by('create_issue')).to eq(project)
    end

    it 'returns nil when nothing denies the tool' do
      create(:ai_tool_rule, namespace: namespace, tool_name: 'create_issue', local_access: :allow)

      expect(governance.denied_by('create_issue')).to be_nil
    end
  end

  describe '.governs?' do
    it 'is true when both flags are enabled for the root namespace' do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: namespace,
        duo_workflow_local_tool_governance: namespace)

      expect(described_class.governs?(project)).to be(true)
    end

    it 'is false when the enforcement flag is disabled' do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)

      expect(described_class.governs?(project)).to be(false)
    end

    it 'is false when local tool governance is disabled' do
      stub_feature_flags(duo_workflow_local_tool_governance: false)

      expect(described_class.governs?(project)).to be(false)
    end
  end
end
