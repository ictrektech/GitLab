# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::Sessions::ClickHouseFinder, :click_house, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:reference_time) { Time.current.change(usec: 0) }

  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) { create(:group_member, :guest, member_role: member_role, user: user, group: group) }

  let(:project_session) do
    session_row(id: 1, namespace: project.project_namespace, project: project, user: user,
      flow_type: 'chat', session_started_at: reference_time - 3.hours)
  end

  let(:subgroup_project_session) do
    session_row(id: 2, namespace: subgroup_project.project_namespace, project: subgroup_project, user: other_user,
      source: :claude_code_compliance_api, flow_type: 'claude_code', session_started_at: reference_time - 2.hours)
  end

  let(:subgroup_namespace_session) do
    session_row(id: 3, namespace: subgroup, user: user, source: :claude_code_glab,
      session_started_at: reference_time - 1.hour)
  end

  let(:group_namespace_session) do
    session_row(id: 4, namespace: group, user: other_user, flow_type: 'software_development',
      session_started_at: reference_time - 1.hour)
  end

  let(:outside_session) do
    session_row(id: 5, namespace: other_project.project_namespace, project: other_project, user: user,
      session_started_at: reference_time)
  end

  let(:namespace) { group }
  let(:current_user) { user }
  let(:params) { {} }

  subject(:result_ids) do
    query = described_class.new(current_user: current_user, namespace: namespace, params: params).execute

    ClickHouse::Client.select(query.to_sql, :main).pluck('id')
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )

    insert_sessions(project_session, subgroup_project_session, subgroup_namespace_session, group_namespace_session,
      outside_session)
  end

  describe '#execute' do
    it 'returns sessions in the group and its descendants, newest first, ties broken by id' do
      expect(result_ids).to eq([4, 3, 2, 1])
    end

    context 'when the namespace is a project namespace' do
      let(:namespace) { project.project_namespace }

      it 'returns only the sessions of that project' do
        expect(result_ids).to eq([1])
      end
    end

    context 'when the user cannot read agent artifacts' do
      let(:current_user) { create(:user) }

      it 'returns nothing' do
        expect(result_ids).to be_empty
      end
    end

    context 'when a row has several replicated versions' do
      before do
        insert_sessions(project_session.merge(flow_type: 'software_development',
          _siphon_replicated_at: reference_time + 1.minute))
      end

      it 'uses the latest version', :aggregate_failures do
        expect(result_ids).to eq([4, 3, 2, 1])
        expect(described_class.new(current_user: user, namespace: group, params: { flow_type: 'chat' }).execute)
          .to satisfy { |query| ClickHouse::Client.select(query.to_sql, :main).empty? }
      end
    end

    context 'when the latest version of a row is deleted' do
      before do
        insert_sessions(project_session.merge(_siphon_deleted: true, _siphon_replicated_at: reference_time + 1.minute))
      end

      it 'excludes the row' do
        expect(result_ids).to eq([4, 3, 2])
      end
    end

    describe 'filters' do
      using RSpec::Parameterized::TableSyntax

      where(:params, :expected_ids) do
        { agent_class: :internal_dap }              | [4, 1]
        { agent_class: :external }                  | [3, 2]
        { agent_class: :all }                       | [4, 3, 2, 1]
        { flow_type: 'chat' }                       | [1]
        { not: { flow_type: 'chat' } }              | [4, 3, 2]
        { user_id: 0 }                              | []
        { project_path: 'does/not-exist' }          | []
        { not: { project_path: 'does/not-exist' } } | [4, 3, 2, 1]
        { id: 2 }                                   | [2]
        { id: 5 }                                   | []
      end

      with_them do
        it 'returns the matching sessions in order' do
          expect(result_ids).to eq(expected_ids)
        end
      end

      context 'when filtering by user' do
        let(:params) { { user_id: other_user.id } }

        it 'returns sessions triggered by the user' do
          expect(result_ids).to eq([4, 2])
        end
      end

      context 'when excluding a user' do
        let(:params) { { not: { user_id: other_user.id } } }

        it 'returns sessions triggered by anyone else' do
          expect(result_ids).to eq([3, 1])
        end
      end

      context 'when filtering by project path' do
        let(:params) { { project_path: subgroup_project.full_path } }

        it 'returns only that project\'s sessions' do
          expect(result_ids).to eq([2])
        end
      end

      context 'with a project path outside the namespace' do
        let(:params) { { project_path: other_project.full_path } }

        it 'returns nothing' do
          expect(result_ids).to be_empty
        end
      end

      context 'when excluding a project path' do
        let(:params) { { not: { project_path: project.full_path } } }

        it 'keeps namespace-scoped sessions' do
          expect(result_ids).to eq([4, 3, 2])
        end
      end

      context 'when filtering by start time' do
        let(:params) do
          { session_started_after: reference_time - 2.hours, session_started_before: reference_time - 90.minutes }
        end

        it 'applies inclusive bounds' do
          expect(result_ids).to eq([2])
        end
      end
    end
  end

  def session_row(id:, namespace:, user:, session_started_at:, project: nil, source: :gitlab_duo, flow_type: nil)
    {
      id: id,
      namespace_id: namespace.id,
      project_id: project&.id,
      user_id: user.id,
      workflow_id: source == :gitlab_duo ? id : nil,
      external_xid: source == :gitlab_duo ? nil : "xid-#{id}",
      source: Ai::Governance::Session.sources.fetch(source),
      flow_type: flow_type,
      created_at: session_started_at,
      updated_at: session_started_at,
      session_started_at: session_started_at,
      traversal_path: namespace.traversal_path(with_organization: true),
      _siphon_replicated_at: reference_time,
      _siphon_deleted: false
    }
  end

  def insert_sessions(*rows)
    expect(clickhouse_fixture(:siphon_ai_governance_sessions, rows)).to be(true)
  end
end
