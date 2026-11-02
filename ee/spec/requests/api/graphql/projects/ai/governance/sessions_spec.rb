# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying AI governance sessions for a project', :click_house,
  feature_category: :compliance_management do
  include GraphqlHelpers
  include Ai::Governance::SessionClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sibling_project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:reference_time) { Time.current.change(usec: 0) }

  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) do
    create(:project_member, :guest, member_role: member_role, user: owner, project: project)
  end

  let(:current_user) { owner }
  let(:query) do
    <<~GRAPHQL
      query {
        project(fullPath: "#{project.full_path}") {
          aiGovernanceSessions(first: 10) {
            count
            nodes { id source project { fullPath } triggeredBy { username } }
          }
        }
      }
    GRAPHQL
  end

  def sessions
    graphql_data.dig('project', 'aiGovernanceSessions')
  end

  def gid(id)
    ::Gitlab::GlobalId.build(model_name: 'Ai::Governance::Session', id: id).to_s
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    insert_ai_governance_sessions(
      ai_governance_session_row(id: 1, namespace: project.project_namespace, project: project, user: owner,
        session_started_at: reference_time - 2.hours),
      ai_governance_session_row(id: 2, namespace: project.project_namespace, project: project, user: owner,
        source: :claude_code_compliance_api, session_started_at: reference_time - 1.hour),
      ai_governance_session_row(id: 3, namespace: sibling_project.project_namespace, project: sibling_project,
        user: owner, session_started_at: reference_time - 1.hour),
      ai_governance_session_row(id: 4, namespace: group, user: owner, session_started_at: reference_time - 1.hour)
    )
  end

  it 'returns only the sessions of the project, newest first', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(graphql_errors).to be_nil
    expect(sessions['count']).to eq(2)
    expect(sessions['nodes']).to eq([
      { 'id' => gid(2), 'source' => 'CLAUDE_CODE_COMPLIANCE_API',
        'project' => { 'fullPath' => project.full_path }, 'triggeredBy' => { 'username' => owner.username } },
      { 'id' => gid(1), 'source' => 'GITLAB_DUO',
        'project' => { 'fullPath' => project.full_path }, 'triggeredBy' => { 'username' => owner.username } }
    ])
  end

  context 'when the user cannot read agent artifacts' do
    let(:current_user) { non_member }

    it 'returns null' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data['project']).to be_nil.or(include('aiGovernanceSessions' => nil))
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(ai_governance_sessions_api: false)
    end

    it 'returns no sessions' do
      post_graphql(query, current_user: current_user)

      expect(sessions['nodes']).to be_empty
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    let_it_be(:pg_duo_session) do
      create(:ai_governance_session, namespace: project.project_namespace, project: project, user: owner,
        session_started_at: reference_time - 2.hours)
    end

    let_it_be(:pg_external_session) do
      create(:ai_governance_session, :external, namespace: project.project_namespace, project: project, user: owner,
        session_started_at: reference_time - 1.hour)
    end

    let_it_be(:pg_sibling_session) do
      create(:ai_governance_session, namespace: sibling_project.project_namespace, project: sibling_project,
        user: owner, session_started_at: reference_time - 1.hour)
    end

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    it 'returns only the sessions of the project from PostgreSQL, newest first', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(sessions['count']).to eq(2)
      expect(sessions['nodes']).to eq([
        { 'id' => pg_external_session.to_global_id.to_s, 'source' => 'CLAUDE_CODE_COMPLIANCE_API',
          'project' => { 'fullPath' => project.full_path }, 'triggeredBy' => { 'username' => owner.username } },
        { 'id' => pg_duo_session.to_global_id.to_s, 'source' => 'GITLAB_DUO',
          'project' => { 'fullPath' => project.full_path }, 'triggeredBy' => { 'username' => owner.username } }
      ])
    end
  end

  it 'avoids N+1 queries when loading users' do
    post_graphql(query, current_user: current_user)
    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

    insert_ai_governance_sessions(
      ai_governance_session_row(id: 5, namespace: project.project_namespace, project: project, user: create(:user),
        session_started_at: reference_time - 3.hours)
    )

    expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
  end

  describe 'link fields' do
    # A chat workflow of another user: :read_agent_artifacts on the project doesn't grant :read_duo_workflow on it.
    let_it_be(:workflow) { create(:duo_workflows_workflow, :agentic_chat, project: project) }
    let_it_be(:merge_request_link) { create(:duo_workflows_workflow_merge_request, workflow: workflow) }
    let_it_be(:note_link) do
      create(:duo_workflows_workflow_note, workflow: workflow, note: create(:note_on_issue, project: project))
    end

    let_it_be(:work_item_link) { create(:duo_workflows_workflow_work_item, workflow: workflow) }

    let(:query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            aiGovernanceSessions(first: 10) {
              nodes {
                id
                mergeRequestLinks { nodes { linkType mergeRequest { id } } }
                noteLinks { nodes { linkType note { id } } }
                workItemLinks { nodes { linkType workItem { id } } }
              }
            }
          }
        }
      GRAPHQL
    end

    before_all do
      # Guests can't read merge requests of private projects.
      group.add_reporter(owner)
    end

    before do
      insert_ai_governance_sessions(
        ai_governance_session_row(id: 6, namespace: project.project_namespace, project: project, user: owner,
          session_started_at: reference_time - 30.minutes).merge(workflow_id: workflow.id)
      )
    end

    it 'returns the links of a GitLab Duo session and none for an external session', :aggregate_failures do
      expect(current_user.can?(:read_duo_workflow, workflow)).to be(false)

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil

      nodes = sessions['nodes'].index_by { |node| node['id'] }

      expect(nodes[gid(2)]).to include(
        'mergeRequestLinks' => { 'nodes' => [] }, 'noteLinks' => { 'nodes' => [] },
        'workItemLinks' => { 'nodes' => [] }
      )
      expect(nodes[gid(6)]).to include(
        'mergeRequestLinks' => { 'nodes' => [
          { 'linkType' => 'SOURCE', 'mergeRequest' => { 'id' => global_id_of(merge_request_link.merge_request).to_s } }
        ] },
        'noteLinks' => { 'nodes' => [
          { 'linkType' => 'CREATED', 'note' => { 'id' => global_id_of(note_link.note).to_s } }
        ] },
        'workItemLinks' => { 'nodes' => [
          { 'linkType' => 'SOURCE', 'workItem' => { 'id' => global_id_of(work_item_link.work_item).to_s } }
        ] }
      )
    end
  end
end
