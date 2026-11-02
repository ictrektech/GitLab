# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::SessionsFinder, feature_category: :compliance_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:reference_time) { Time.current }

  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) { create(:group_member, :guest, member_role: member_role, user: user, group: group) }

  # The factory's workflow_id sequence can equal a real workflow id used below in the same namespace.
  let_it_be(:project_session) do
    create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
      workflow_id: non_existing_record_id, flow_type: 'chat', session_started_at: reference_time - 3.hours)
  end

  let_it_be(:subgroup_project_session) do
    create(:ai_governance_session, :external, namespace: subgroup_project.project_namespace,
      project: subgroup_project, user: other_user, flow_type: 'claude_code',
      session_started_at: reference_time - 2.hours)
  end

  let_it_be(:subgroup_namespace_session) do
    create(:ai_governance_session, :external, namespace: subgroup, user: user, source: :claude_code_glab,
      session_started_at: reference_time - 1.hour)
  end

  let_it_be(:group_namespace_session) do
    create(:ai_governance_session, namespace: group, user: other_user, flow_type: 'software_development',
      session_started_at: reference_time - 1.hour)
  end

  let_it_be(:outside_session) do
    create(:ai_governance_session, namespace: other_project.project_namespace, project: other_project, user: user)
  end

  let(:namespace) { group }
  let(:current_user) { user }
  let(:params) { {} }

  subject(:results) { described_class.new(current_user: current_user, namespace: namespace, params: params).execute }

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
  end

  describe '#execute' do
    it 'returns sessions in the group and its descendants, newest first, ties broken by id' do
      expect(results.to_a).to eq([
        group_namespace_session, subgroup_namespace_session, subgroup_project_session, project_session
      ])
    end

    it 'preloads the associations the list renders', :aggregate_failures do
      session = results.find { |s| s.id == project_session.id }

      expect(session.association(:project)).to be_loaded
      expect(session.association(:user)).to be_loaded
      expect(session.association(:namespace)).to be_loaded
    end

    context 'when the namespace is a project namespace' do
      let(:namespace) { project.project_namespace }

      it 'returns only the sessions of that project' do
        expect(results).to contain_exactly(project_session)
      end
    end

    context 'when the user cannot read agent artifacts' do
      let(:current_user) { create(:user) }

      it 'returns nothing' do
        expect(results).to be_empty
      end
    end

    context 'with a private messaging session' do
      let_it_be(:private_workflow) do
        create(:duo_workflows_workflow, project: project, user: user,
          messaging_callback_context: { 'adapter' => 'slack' })
      end

      let_it_be(:shared_workflow) do
        create(:duo_workflows_workflow, project: project, user: user,
          messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })
      end

      let_it_be(:private_session) do
        create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
          workflow_id: private_workflow.id)
      end

      let_it_be(:shared_session) do
        create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
          workflow_id: shared_workflow.id)
      end

      it 'hides sessions whose workflow is private to its invoker', :aggregate_failures do
        expect(results).to include(shared_session)
        expect(results).not_to include(private_session)
      end

      context 'when filtering by user' do
        let(:params) { { user_id: user.id } }

        it 'hides sessions whose workflow is private to its invoker', :aggregate_failures do
          expect(results).to include(shared_session)
          expect(results).not_to include(private_session)
        end
      end

      context 'when filtering by the id of a private session' do
        let(:params) { { id: private_session.id } }

        it 'returns nothing' do
          expect(results).to be_empty
        end
      end
    end

    describe 'filters' do
      using RSpec::Parameterized::TableSyntax

      all_sessions = %i[group_namespace_session subgroup_namespace_session subgroup_project_session project_session]

      where(:params, :expected_names) do
        { agent_class: :internal_dap }              | %i[group_namespace_session project_session]
        { agent_class: :external }                  | %i[subgroup_namespace_session subgroup_project_session]
        { agent_class: :all }                       | all_sessions
        { flow_type: 'chat' }                       | %i[project_session]
        { not: { flow_type: 'chat' } }              | (all_sessions - %i[project_session])
        { project_path: 'does/not-exist' }          | []
        { not: { project_path: 'does/not-exist' } } | all_sessions
      end

      with_them do
        it 'returns the matching sessions in order' do
          expect(results.to_a).to eq(expected_names.map { |name| public_send(name) })
        end
      end

      context 'when filtering by id' do
        let(:params) { { id: subgroup_project_session.id } }

        it 'returns only that session' do
          expect(results.to_a).to eq([subgroup_project_session])
        end

        it 'does not walk the namespaces with the in-operator optimization' do
          expect(::Gitlab::Pagination::Keyset::InOperatorOptimization::QueryBuilder).not_to receive(:new)

          results.to_a
        end

        it 'preloads the associations the list renders', :aggregate_failures do
          session = results.first

          expect(session.association(:project)).to be_loaded
          expect(session.association(:user)).to be_loaded
          expect(session.association(:namespace)).to be_loaded
        end

        context 'when the session is outside the namespace' do
          let(:params) { { id: outside_session.id } }

          it 'returns nothing' do
            expect(results).to be_empty
          end
        end
      end

      context 'when filtering by user' do
        let(:params) { { user_id: other_user.id } }

        it 'returns sessions triggered by the user' do
          expect(results.to_a).to eq([group_namespace_session, subgroup_project_session])
        end

        context 'when the user has sessions outside the namespace' do
          let(:params) { { user_id: user.id } }

          it 'returns only the sessions inside it' do
            expect(results.to_a).to eq([subgroup_namespace_session, project_session])
          end
        end

        context 'when also filtering by project path' do
          let(:params) { { user_id: other_user.id, project_path: subgroup_project.full_path } }

          it 'returns only that project\'s sessions' do
            expect(results.to_a).to eq([subgroup_project_session])
          end
        end
      end

      context 'when excluding a user' do
        let(:params) { { not: { user_id: other_user.id } } }

        it 'returns sessions triggered by anyone else' do
          expect(results.to_a).to eq([subgroup_namespace_session, project_session])
        end
      end

      context 'when filtering by project path' do
        let(:params) { { project_path: subgroup_project.full_path } }

        it 'returns only that project\'s sessions' do
          expect(results.to_a).to eq([subgroup_project_session])
        end
      end

      context 'with a project path outside the namespace' do
        let(:params) { { project_path: other_project.full_path } }

        it 'returns nothing' do
          expect(results).to be_empty
        end
      end

      context 'when excluding a project path' do
        let(:params) { { not: { project_path: project.full_path } } }

        it 'keeps namespace-scoped sessions' do
          expect(results.to_a).to eq([group_namespace_session, subgroup_namespace_session, subgroup_project_session])
        end
      end

      context 'when filtering by start time' do
        let(:params) do
          { session_started_after: reference_time - 2.hours, session_started_before: reference_time - 90.minutes }
        end

        it 'applies inclusive bounds' do
          expect(results.to_a).to eq([subgroup_project_session])
        end
      end
    end
  end

  describe '#count_relation' do
    subject(:count_relation) do
      described_class.new(current_user: current_user, namespace: namespace, params: params).count_relation
    end

    it 'covers the sessions in the group and its descendants' do
      expect(count_relation.count).to eq(4)
    end

    it 'does not walk the namespaces with the in-operator optimization' do
      expect(::Gitlab::Pagination::Keyset::InOperatorOptimization::QueryBuilder).not_to receive(:new)

      count_relation.count
    end

    context 'with filters' do
      let(:params) { { user_id: other_user.id, not: { project_path: subgroup_project.full_path } } }

      it 'applies them' do
        expect(count_relation).to contain_exactly(group_namespace_session)
      end
    end

    context 'when the namespace is a project namespace' do
      let(:namespace) { project.project_namespace }

      it 'covers only the sessions of that project' do
        expect(count_relation).to contain_exactly(project_session)
      end
    end

    context 'when the user cannot read agent artifacts' do
      let(:current_user) { create(:user) }

      it 'returns nothing' do
        expect(count_relation).to be_empty
      end
    end

    # The sync worker and the backfill never store these sessions, so the count skips the costly check.
    context 'with a private messaging session' do
      let_it_be(:private_workflow) do
        create(:duo_workflows_workflow, project: project, user: user,
          messaging_callback_context: { 'adapter' => 'slack' })
      end

      let_it_be(:private_session) do
        create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
          workflow_id: private_workflow.id)
      end

      it 'does not apply the private messaging check' do
        expect(count_relation).to include(private_session)
      end
    end
  end
end
