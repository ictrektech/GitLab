# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ExternalAgents::AgentIdentitiesFinder, feature_category: :software_composition_analysis do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user) }

  let_it_be(:project_identity) do
    create(:ai_agent_identity, project: project, user: user, agent_type: 'claude-code', last_synced_at: 1.day.ago)
  end

  let_it_be(:subgroup_identity) do
    create(:ai_agent_identity, project: subgroup_project, agent_type: 'cursor', last_synced_at: 2.days.ago)
  end

  let_it_be(:revoked_identity) do
    create(:ai_agent_identity, project: project, agent_type: 'codex', revoked_at: Time.current)
  end

  let_it_be(:other_identity) { create(:ai_agent_identity) }

  let(:params) { {} }

  subject(:identities) { described_class.new(parent, params).execute }

  context 'for a group' do
    let(:parent) { group }

    it 'returns the identities in its projects and subgroups, most recently synced first' do
      expect(identities).to eq([project_identity, subgroup_identity, revoked_identity])
    end

    context 'with agent types' do
      let(:params) { { agent_types: %w[cursor codex] } }

      it { is_expected.to contain_exactly(subgroup_identity, revoked_identity) }
    end

    context 'with a user ID' do
      let(:params) { { user_id: user.id } }

      it { is_expected.to contain_exactly(project_identity) }
    end

    context 'with a status' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:stale_identity) { create(:ai_agent_identity, project: project, last_synced_at: 31.days.ago) }

      where(:status, :expected) do
        :active | [ref(:project_identity), ref(:subgroup_identity)]
        :inactive | [ref(:stale_identity)]
        :revoked | [ref(:revoked_identity)]
      end

      with_them do
        let(:params) { { status: status } }

        it { is_expected.to match_array(expected) }
      end
    end
  end

  context 'for a project' do
    let(:parent) { project }

    it { is_expected.to eq([project_identity, revoked_identity]) }
  end
end
