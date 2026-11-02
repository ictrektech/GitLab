# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::Governance::ProjectSessionsResolver, :click_house,
  feature_category: :compliance_management do
  include GraphqlHelpers
  include Ai::Governance::SessionClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sibling_project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) do
    create(:project_member, :guest, member_role: member_role, user: user, project: project)
  end

  let_it_be(:reference_time) { Time.current.change(usec: 0) }

  let(:current_user) { user }
  let(:args) { {} }

  subject(:resolved) { resolve(described_class, obj: project, args: args, ctx: { current_user: current_user }) }

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    insert_ai_governance_sessions(
      ai_governance_session_row(id: 1, namespace: project.project_namespace, project: project, user: user,
        session_started_at: reference_time - 2.hours),
      ai_governance_session_row(id: 2, namespace: project.project_namespace, project: project, user: user,
        source: :claude_code_glab, session_started_at: reference_time - 1.hour),
      ai_governance_session_row(id: 3, namespace: sibling_project.project_namespace, project: sibling_project,
        user: user, session_started_at: reference_time - 1.hour),
      ai_governance_session_row(id: 4, namespace: group, user: user, session_started_at: reference_time - 1.hour)
    )
  end

  def resolved_ids
    ai_governance_session_ids(resolved.items)
  end

  it 'does not expose a project path argument' do
    expect(described_class.arguments.keys).not_to include('projectPath')
  end

  it 'returns only the sessions of the project, newest first' do
    expect(resolved_ids).to eq([2, 1])
  end

  context 'with an agent class filter' do
    let(:args) { { agent_class: 'INTERNAL_DAP' } }

    it 'filters on the session source' do
      expect(resolved_ids).to eq([1])
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(ai_governance_sessions_api: false)
    end

    it 'returns no sessions' do
      expect(resolved).to be_empty
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    let_it_be(:pg_older_session) do
      create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
        session_started_at: reference_time - 2.hours)
    end

    let_it_be(:pg_newer_session) do
      create(:ai_governance_session, :external, namespace: project.project_namespace, project: project, user: user,
        session_started_at: reference_time - 1.hour)
    end

    let_it_be(:pg_sibling_session) do
      create(:ai_governance_session, namespace: sibling_project.project_namespace, project: sibling_project,
        user: user, session_started_at: reference_time - 1.hour)
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'returns only the sessions of the project from PostgreSQL, newest first' do
      expect(::Ai::Governance::Sessions::ClickHouseFinder).not_to receive(:new)

      expect(resolved.to_a).to eq([pg_newer_session, pg_older_session])
    end

    context 'with an agent class filter' do
      let(:args) { { agent_class: 'INTERNAL_DAP' } }

      it 'filters on the session source' do
        expect(resolved.to_a).to eq([pg_older_session])
      end
    end
  end

  context 'when the user cannot read agent artifacts' do
    let(:current_user) { create(:user) }

    it 'returns no sessions' do
      expect(resolved_ids).to be_empty
    end
  end
end
