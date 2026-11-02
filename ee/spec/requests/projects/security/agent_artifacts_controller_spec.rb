# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::AgentArtifactsController, feature_category: :compliance_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  describe 'GET #download' do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:audit_event) do
      create(:audit_events_ai_audit_event, workflow_id: workflow.id, event_name: 'ai_agent_session_started')
    end

    subject(:request) { get download_project_security_agent_artifact_path(project, workflow.id) }

    context 'when user is not authorized' do
      before_all do
        project.add_maintainer(user)
      end

      before do
        sign_in(user)
        stub_licensed_features(project_level_compliance_dashboard: true)
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user is authorized' do
      before_all do
        project.add_owner(user)
      end

      before do
        sign_in(user)
        stub_licensed_features(project_level_compliance_dashboard: true)
      end

      it 'returns the session artifact as a JSON attachment', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.media_type).to eq('application/json')
        expect(response.headers['Content-Disposition'])
          .to include('attachment', "session-artifact-#{workflow.id}.json")

        payload = Gitlab::Json.safe_parse(response.body)
        expect(payload['session']).to include(
          'id' => workflow.id,
          'workflow_definition' => workflow.workflow_definition
        )
        expect(payload['session']['project']).to include('full_path' => project.full_path)
        expect(payload['audit_events']).to contain_exactly(
          a_hash_including('event_name' => 'ai_agent_session_started')
        )
      end

      it 'returns 404 when the session artifact does not exist' do
        get download_project_security_agent_artifact_path(project, non_existing_record_id)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 404 for a session belonging to another project' do
        other_workflow = create(:duo_workflows_workflow)

        get download_project_security_agent_artifact_path(project, other_workflow.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns 404 for an invoker-private messaging session' do
        messaging_workflow = create(:duo_workflows_workflow, project: project,
          messaging_callback_context: { 'adapter' => 'slack' })

        get download_project_security_agent_artifact_path(project, messaging_workflow.id)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'serves a note-mention session (gitlab_duo_note)' do
        note_mention_workflow = create(:duo_workflows_workflow, project: project,
          messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })

        get download_project_security_agent_artifact_path(project, note_mention_workflow.id)

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'serves the session when analytics are backed by ClickHouse and no Postgres artifact exists' do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
        allow(::ClickHouse::Client).to receive(:select).and_return([])

        request

        expect(response).to have_gitlab_http_status(:ok)
        payload = Gitlab::Json.safe_parse(response.body)
        expect(payload['session']).to include('id' => workflow.id)
        expect(payload['audit_events']).to eq([])
      end

      context 'when agent_artifacts_page feature flag is disabled' do
        before do
          stub_feature_flags(agent_artifacts_page: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when project_level_compliance_dashboard is not available' do
        before do
          stub_licensed_features(project_level_compliance_dashboard: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  describe 'GET #download_session', :click_house do
    include Ai::Governance::SessionClickHouseHelpers

    let_it_be(:other_project) { create(:project, group: group) }
    let_it_be(:session_started_at) { Time.current.change(usec: 0) }

    let(:session_row) do
      ai_governance_session_row(id: 11, namespace: project.project_namespace, project: project, user: user,
        source: :claude_code_glab, flow_type: 'claude_code', session_started_at: session_started_at)
    end

    let(:session_id) { session_row[:id] }

    subject(:request) { get download_session_project_security_agent_artifact_path(project, session_id) }

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      insert_ai_governance_sessions(
        session_row,
        ai_governance_session_row(id: 12, namespace: other_project.project_namespace, project: other_project,
          user: user, source: :claude_code_glab, session_started_at: session_started_at),
        ai_governance_session_row(id: 13, namespace: project.project_namespace, project: project, user: user,
          session_started_at: session_started_at)
      )
      clickhouse_fixture(:ai_audit_events, [
        {
          id: SecureRandom.uuid,
          event_name: 'run_tool',
          created_at: session_started_at + 1.minute,
          author_id: user.id,
          project_id: project.id,
          workflow_id: 0,
          ai_governance_session_id: session_row[:id],
          traversal_path: project.project_namespace.traversal_path(with_organization: true)
        }
      ])
      sign_in(user)
      stub_licensed_features(project_level_compliance_dashboard: true)
    end

    context 'when user is not authorized' do
      before_all do
        project.add_maintainer(user)
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when user is authorized' do
      before_all do
        project.add_owner(user)
        other_project.add_owner(user)
      end

      it 'returns the session artifact as a JSON attachment', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.media_type).to eq('application/json')
        expect(response.headers['Content-Disposition'])
          .to include('attachment', "session-artifact-#{session_row[:id]}.json")

        payload = Gitlab::Json.safe_parse(response.body)
        expect(payload['session']).to include(
          'id' => session_row[:id],
          'source' => 'claude_code_glab',
          'flow_type' => 'claude_code'
        )
        expect(payload['session']['project']).to include('full_path' => project.full_path)
        expect(payload['audit_events']).to contain_exactly(a_hash_including('event_name' => 'run_tool'))
      end

      context 'when the session belongs to another project' do
        let(:session_id) { 12 }

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the session is a GitLab Duo session' do
        let(:session_id) { 13 }

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when ai_governance_sessions_api feature flag is disabled' do
        before do
          stub_feature_flags(ai_governance_sessions_api: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when ClickHouse is not enabled for analytics' do
        before do
          allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when agent_artifacts_page feature flag is disabled' do
        before do
          stub_feature_flags(agent_artifacts_page: false)
        end

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
