# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying AI governance sessions for a group', :click_house, feature_category: :compliance_management do
  include GraphqlHelpers
  include Ai::Governance::SessionClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:reference_time) { Time.current.change(usec: 0) }

  # aiGovernanceSessions requires :read_agent_artifacts, a custom ability granted via member roles.
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) { create(:group_member, :guest, member_role: member_role, user: owner, group: group) }

  let(:project_duo_session) do
    ai_governance_session_row(id: 1, namespace: project.project_namespace, project: project, user: owner,
      flow_type: 'chat', session_started_at: reference_time - 3.hours)
  end

  let(:namespace_duo_session) do
    ai_governance_session_row(id: 2, namespace: subgroup, user: owner, flow_type: 'agentic_chat',
      session_started_at: reference_time - 2.hours)
  end

  let(:external_session) do
    ai_governance_session_row(id: 3, namespace: group, user: owner, source: :claude_code_glab,
      flow_type: 'claude_code', agent_type: 'claude-code', session_started_at: reference_time - 1.hour)
  end

  let(:current_user) { owner }
  let(:arguments) { 'first: 10' }
  let(:query) do
    <<~GRAPHQL
      query {
        group(fullPath: "#{group.full_path}") {
          aiGovernanceSessions(#{arguments}) {
            count
            nodes {
              id
              sessionId
              flowType
              agentType
              source
              sessionStartedAt
              webPath
              downloadPath
              project { id fullPath }
              triggeredBy { id username }
            }
            pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
          }
        }
      }
    GRAPHQL
  end

  def sessions
    graphql_data.dig('group', 'aiGovernanceSessions')
  end

  def node_ids
    sessions['nodes'].pluck('id')
  end

  def gid(row)
    ::Gitlab::GlobalId.build(model_name: 'Ai::Governance::Session', id: row[:id]).to_s
  end

  # A method, not a `let`: the example groups below are at the memoized helper limit.
  def old_session
    ai_governance_session_row(id: 4, namespace: group, user: owner, flow_type: 'chat',
      session_started_at: reference_time - 200.days)
  end

  def audit_event_row(created_at:, workflow_id: 0, ai_governance_session_id: 0)
    {
      id: SecureRandom.uuid,
      event_name: 'run_tool',
      created_at: created_at,
      author_id: owner.id,
      project_id: project.id,
      workflow_id: workflow_id,
      ai_governance_session_id: ai_governance_session_id,
      traversal_path: project.project_namespace.traversal_path(with_organization: true)
    }
  end

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    insert_ai_governance_sessions(project_duo_session, namespace_duo_session, external_session, old_session)
  end

  it 'returns the sessions of the group and its descendants, newest first', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(graphql_errors).to be_nil
    expect(sessions['count']).to eq(3)
    expect(node_ids).to eq([external_session, namespace_duo_session, project_duo_session].map { |s| gid(s) })
  end

  it 'returns the field values of each source', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    external, namespace_duo, project_duo = sessions['nodes']

    expect(external).to include(
      'sessionId' => external_session[:external_xid],
      'flowType' => 'claude_code',
      'agentType' => 'claude-code',
      'source' => 'CLAUDE_CODE_GLAB',
      'webPath' => nil,
      'downloadPath' => download_session_group_security_agent_artifact_path(group, external_session[:id]),
      'project' => nil,
      'triggeredBy' => { 'id' => global_id_of(owner).to_s, 'username' => owner.username }
    )
    expect(namespace_duo).to include(
      'sessionId' => namespace_duo_session[:workflow_id].to_s,
      'source' => 'GITLAB_DUO',
      'webPath' => nil,
      'downloadPath' => download_group_security_agent_artifact_path(subgroup, namespace_duo_session[:workflow_id]),
      'project' => nil
    )
    expect(project_duo).to include(
      'source' => 'GITLAB_DUO',
      'sessionStartedAt' => project_duo_session[:session_started_at].iso8601,
      'webPath' => project_automate_agent_session_path(project, project_duo_session[:workflow_id]),
      'downloadPath' => download_project_security_agent_artifact_path(project, project_duo_session[:workflow_id]),
      'project' => { 'id' => global_id_of(project).to_s, 'fullPath' => project.full_path }
    )
  end

  context 'with filters' do
    let(:arguments) do
      %(first: 10, agentClass: INTERNAL_DAP, not: { flowType: "chat" }, triggeredByUserId: "#{global_id_of(owner)}")
    end

    it 'applies them', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(node_ids).to eq([gid(namespace_duo_session)])
    end
  end

  describe 'the session start window' do
    it 'lists only the last 180 days unless a window is given', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(node_ids).not_to include(gid(old_session))
      expect(sessions['count']).to eq(3)
    end

    context 'with a window around an older session' do
      let(:arguments) do
        %(first: 10, sessionStartedAfter: "#{(reference_time - 210.days).iso8601}",
          sessionStartedBefore: "#{(reference_time - 190.days).iso8601}")
      end

      it 'returns the sessions in that window' do
        post_graphql(query, current_user: current_user)

        expect(node_ids).to eq([gid(old_session)])
      end
    end

    context 'with a window wider than 180 days' do
      let(:arguments) { %(first: 10, sessionStartedAfter: "#{(reference_time - 400.days).iso8601}") }

      it 'moves sessionStartedAfter up to 180 days before now', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(node_ids).not_to include(gid(old_session))
        expect(sessions['count']).to eq(3)
      end
    end

    context 'with sessionStartedBefore in the future' do
      let(:arguments) { %(first: 10, sessionStartedBefore: "#{(reference_time + 400.days).iso8601}") }

      it 'still lists the last 180 days' do
        post_graphql(query, current_user: current_user)

        expect(node_ids).to contain_exactly(gid(external_session), gid(namespace_duo_session), gid(project_duo_session))
      end
    end

    context 'with an id' do
      let(:arguments) { %(id: "#{gid(old_session)}") }

      it 'finds a session older than 180 days' do
        post_graphql(query, current_user: current_user)

        expect(node_ids).to eq([gid(old_session)])
      end
    end
  end

  context 'with a count limit' do
    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            aiGovernanceSessions(first: 1) { count(limit: 1) }
          }
        }
      GRAPHQL
    end

    it 'returns limit + 1' do
      post_graphql(query, current_user: current_user)

      expect(sessions['count']).to eq(2)
    end

    it 'stops the ClickHouse count at limit + 1' do
      allow(::ClickHouse::Client).to receive(:select).and_call_original

      post_graphql(query, current_user: current_user)

      expect(::ClickHouse::Client).to have_received(:select)
        .with(having_attributes(to_sql: a_string_matching(/count\(\).*LIMIT 2/m)), :main)
    end
  end

  context 'with an invalid session start range' do
    let(:arguments) do
      %(first: 10, sessionStartedAfter: "#{reference_time.iso8601}",
        sessionStartedBefore: "#{(reference_time - 1.hour).iso8601}")
    end

    it 'returns an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include('sessionStartedAfter must not be after sessionStartedBefore')
    end
  end

  context 'with pagination' do
    let(:arguments) { 'first: 2' }

    it 'pages through the sessions in order', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(node_ids).to eq([gid(external_session), gid(namespace_duo_session)])
      expect(sessions['pageInfo']['hasNextPage']).to be(true)

      end_cursor = sessions['pageInfo']['endCursor']
      post_graphql(query.sub('first: 2', %(first: 2, after: "#{end_cursor}")), current_user: current_user)

      expect(node_ids).to eq([gid(project_duo_session)])
      expect(sessions['pageInfo']).to include('hasNextPage' => false, 'hasPreviousPage' => true)
    end
  end

  context 'when the user cannot read agent artifacts' do
    let(:current_user) { non_member }

    it 'returns null' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data.dig('group', 'aiGovernanceSessions')).to be_nil
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(ai_governance_sessions_api: false)
    end

    it 'returns no sessions', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(sessions['nodes']).to be_empty
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: owner) }

    let_it_be(:pg_project_duo_session) do
      create(:ai_governance_session, namespace: project.project_namespace, project: project, user: owner,
        workflow_id: workflow.id, flow_type: 'chat', session_started_at: reference_time - 3.hours)
    end

    let_it_be(:pg_namespace_duo_session) do
      create(:ai_governance_session, namespace: subgroup, user: owner, flow_type: 'agentic_chat',
        session_started_at: reference_time - 2.hours)
    end

    let_it_be(:pg_external_session) do
      create(:ai_governance_session, :external, namespace: group, user: owner, source: :claude_code_glab,
        flow_type: 'claude_code', agent_type: 'claude-code', session_started_at: reference_time - 1.hour)
    end

    let(:pg_sessions) { [pg_external_session, pg_namespace_duo_session, pg_project_duo_session] }

    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    def pg_old_session
      @pg_old_session ||= create(:ai_governance_session, namespace: group, user: owner, flow_type: 'chat',
        session_started_at: reference_time - 200.days)
    end

    it 'returns the sessions from PostgreSQL, newest first', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(sessions['count']).to eq(3)
      expect(node_ids).to eq(pg_sessions.map { |session| session.to_global_id.to_s })
    end

    describe 'the session start window' do
      it 'lists only the last 180 days unless a window is given', :aggregate_failures do
        old_gid = pg_old_session.to_global_id.to_s

        post_graphql(query, current_user: current_user)

        expect(node_ids).not_to include(old_gid)
        expect(sessions['count']).to eq(3)
      end

      context 'with a window around an older session' do
        let(:arguments) do
          %(first: 10, sessionStartedAfter: "#{(reference_time - 210.days).iso8601}",
            sessionStartedBefore: "#{(reference_time - 190.days).iso8601}")
        end

        it 'returns the sessions in that window' do
          old_gid = pg_old_session.to_global_id.to_s

          post_graphql(query, current_user: current_user)

          expect(node_ids).to eq([old_gid])
        end
      end

      context 'with an id' do
        let(:arguments) { %(id: "#{pg_old_session.to_global_id}") }

        it 'finds a session older than 180 days' do
          post_graphql(query, current_user: current_user)

          expect(node_ids).to eq([pg_old_session.to_global_id.to_s])
        end
      end
    end

    it 'returns the field values of each source', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      external, namespace_duo, project_duo = sessions['nodes']

      expect(external).to include(
        'sessionId' => pg_external_session.external_xid,
        'flowType' => 'claude_code',
        'agentType' => 'claude-code',
        'source' => 'CLAUDE_CODE_GLAB',
        'webPath' => nil,
        'downloadPath' => nil,
        'project' => nil
      )
      expect(namespace_duo).to include('source' => 'GITLAB_DUO', 'project' => nil)
      expect(project_duo).to include(
        'sessionId' => workflow.id.to_s,
        'source' => 'GITLAB_DUO',
        'sessionStartedAt' => pg_project_duo_session.session_started_at.iso8601,
        'webPath' => project_automate_agent_session_path(project, workflow.id),
        'project' => { 'id' => global_id_of(project).to_s, 'fullPath' => project.full_path }
      )
    end

    context 'with pagination' do
      let(:arguments) { 'first: 2' }

      it 'pages through the sessions in order', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(node_ids).to eq(pg_sessions.first(2).map { |session| session.to_global_id.to_s })
        expect(sessions['count']).to eq(3)
        expect(sessions['pageInfo']['hasNextPage']).to be(true)

        end_cursor = sessions['pageInfo']['endCursor']
        post_graphql(query.sub('first: 2', %(first: 2, after: "#{end_cursor}")), current_user: current_user)

        expect(node_ids).to eq([pg_project_duo_session.to_global_id.to_s])
        expect(sessions['pageInfo']).to include('hasNextPage' => false, 'hasPreviousPage' => true)
      end
    end

    context 'with an id filter' do
      let(:arguments) { %(id: "#{pg_namespace_duo_session.to_global_id}") }

      it 'returns only that session', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(node_ids).to eq([pg_namespace_duo_session.to_global_id.to_s])
        expect(sessions['count']).to eq(1)
      end
    end

    context 'with a count limit' do
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              aiGovernanceSessions(first: 1) { count(limit: 1) }
            }
          }
        GRAPHQL
      end

      it 'returns limit + 1 from the count relation' do
        expect_next_instance_of(::Ai::Governance::SessionsFinder) do |finder|
          expect(finder).to receive(:count_relation).and_call_original
        end

        post_graphql(query, current_user: current_user)

        expect(sessions['count']).to eq(2)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_sessions_api: false)
      end

      it 'returns no sessions', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(sessions['count']).to eq(0)
        expect(sessions['nodes']).to be_empty
      end
    end

    describe 'auditEvents' do
      let_it_be(:duo_event) do
        create(:audit_events_ai_audit_event, workflow_id: workflow.id, author_id: owner.id,
          created_at: pg_project_duo_session.session_started_at + 1.minute)
      end

      let_it_be(:external_event) do
        create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: pg_external_session.id,
          author_id: owner.id, created_at: pg_external_session.session_started_at + 1.minute)
      end

      let_it_be(:skewed_external_event) do
        create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: pg_external_session.id,
          author_id: owner.id, created_at: pg_external_session.session_started_at - 5.minutes)
      end

      let_it_be(:old_external_event) do
        create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: pg_external_session.id,
          author_id: owner.id, created_at: pg_external_session.session_started_at - 1.day - 1.minute)
      end

      let_it_be(:other_session_event) do
        create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: pg_namespace_duo_session.id,
          author_id: owner.id, created_at: pg_external_session.session_started_at + 1.minute)
      end

      let(:session) { pg_project_duo_session }
      let(:query) do
        <<~GRAPHQL
          query {
            group(fullPath: "#{group.full_path}") {
              aiGovernanceSessions(id: "#{session.to_global_id}") {
                nodes {
                  auditEventsCount
                  auditEvents { nodes { id workflowId sessionId } }
                }
              }
            }
          }
        GRAPHQL
      end

      def audit_events
        sessions['nodes'].first['auditEvents']
      end

      it 'returns the events of the workflow of a GitLab Duo session', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(audit_events['nodes'].pluck('id')).to eq([duo_event.cloud_event_id])
        expect(audit_events['nodes'].pluck('workflowId')).to eq([workflow.id.to_s])
      end

      context 'for an external session' do
        let(:session) { pg_external_session }

        it 'returns its events newest first, excluding those over a day before the session start',
          :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(audit_events['nodes'].pluck('id'))
            .to eq([external_event.cloud_event_id, skewed_external_event.cloud_event_id])
          expect(audit_events['nodes'].pluck('sessionId')).to all(eq(session.to_global_id.to_s))
        end
      end

      it 'counts the same events it returns', :aggregate_failures do
        { pg_project_duo_session => 1, pg_external_session => 2 }.each do |session, expected_count|
          post_graphql(query.sub(pg_project_duo_session.to_global_id.to_s, session.to_global_id.to_s),
            current_user: current_user)

          node = sessions['nodes'].first

          expect(graphql_errors).to be_nil
          expect(node['auditEventsCount']).to eq(expected_count)
          expect(node['auditEvents']['nodes'].size).to eq(expected_count)
        end
      end
    end
  end

  # Extra sessions reuse existing projects: each distinct project adds ProjectType's own
  # read_project authorization queries, which are not an N+1 of this field.
  it 'avoids N+1 queries when loading projects, groups and users' do
    post_graphql(query, current_user: current_user)
    control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

    insert_ai_governance_sessions(
      ai_governance_session_row(id: 4, namespace: project.project_namespace, project: project, user: create(:user),
        session_started_at: reference_time - 4.hours),
      ai_governance_session_row(id: 5, namespace: subgroup, user: create(:user),
        session_started_at: reference_time - 5.hours),
      ai_governance_session_row(id: 6, namespace: group, user: create(:user), source: :claude_code_compliance_api,
        session_started_at: reference_time - 6.hours)
    )

    expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
  end

  describe 'auditEvents' do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: owner) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: owner) }

    let(:project_duo_session) do
      ai_governance_session_row(id: 1, namespace: project.project_namespace, project: project, user: owner,
        flow_type: 'chat', session_started_at: reference_time - 3.hours).merge(workflow_id: workflow.id)
    end

    let(:duo_event) do
      audit_event_row(workflow_id: workflow.id, created_at: project_duo_session[:session_started_at] + 1.minute)
    end

    let(:external_event) do
      audit_event_row(ai_governance_session_id: external_session[:id],
        created_at: external_session[:session_started_at] + 1.minute)
    end

    let(:events) do
      [
        duo_event,
        external_event,
        audit_event_row(ai_governance_session_id: external_session[:id],
          created_at: external_session[:session_started_at] - 1.day - 1.minute),
        audit_event_row(ai_governance_session_id: non_existing_record_id,
          created_at: external_session[:session_started_at] + 1.minute),
        audit_event_row(workflow_id: other_workflow.id, created_at: project_duo_session[:session_started_at] + 1.minute)
      ]
    end

    let(:session) { project_duo_session }
    let(:arguments) { %(id: "#{gid(session)}") }
    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            aiGovernanceSessions(#{arguments}) {
              nodes {
                id
                auditEvents { nodes { id eventName workflowId sessionId } }
              }
            }
          }
        }
      GRAPHQL
    end

    def audit_events_of(node)
      node.dig('auditEvents', 'nodes')
    end

    before do
      clickhouse_fixture(:ai_audit_events, events)
    end

    context 'for a GitLab Duo session' do
      it 'returns the events of its workflow', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(sessions['nodes'].pluck('id')).to eq([gid(session)])
        expect(audit_events_of(sessions['nodes'].first)).to contain_exactly(
          { 'id' => duo_event[:id], 'eventName' => 'run_tool', 'workflowId' => workflow.id.to_s, 'sessionId' => nil }
        )
      end

      context 'when the workflow is a private messaging session' do
        let_it_be(:workflow) do
          create(:duo_workflows_workflow, project: project, user: owner,
            messaging_callback_context: { 'adapter' => 'slack' })
        end

        it 'returns no events', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(audit_events_of(sessions['nodes'].first)).to be_empty
        end
      end
    end

    context 'for an external session' do
      let(:session) { external_session }

      it 'returns its events, excluding those over a day before the session start', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(sessions['nodes'].pluck('id')).to eq([gid(session)])
        expect(audit_events_of(sessions['nodes'].first)).to contain_exactly(
          { 'id' => external_event[:id], 'eventName' => 'run_tool', 'workflowId' => nil, 'sessionId' => gid(session) }
        )
      end

      context 'when an event predates the session start by a few minutes' do
        let(:skewed_event) do
          audit_event_row(ai_governance_session_id: external_session[:id],
            created_at: external_session[:session_started_at] - 5.minutes)
        end

        let(:events) { super() + [skewed_event] }

        it 'returns it, allowing for client clock skew' do
          post_graphql(query, current_user: current_user)

          expect(audit_events_of(sessions['nodes'].first).pluck('id'))
            .to contain_exactly(external_event[:id], skewed_event[:id])
        end
      end
    end

    context 'when requested for more than one session' do
      let(:arguments) { 'first: 2' }

      it 'returns the events of the first session and an error for the others', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include(
          [/"auditEvents" field can be requested only for 1 AiGovernanceSession\(s\) at a time./]
        )
        expect(audit_events_of(sessions['nodes'].first).pluck('id')).to contain_exactly(external_event[:id])
        expect(sessions['nodes'].second['auditEvents']).to be_nil
      end
    end

    context 'when requested with first: 1' do
      let(:arguments) { 'first: 1' }

      it 'returns the events of the session', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(audit_events_of(sessions['nodes'].first).pluck('id')).to contain_exactly(external_event[:id])
      end
    end
  end

  describe 'auditEventsCount' do
    let(:duo_session_without_workflow) do
      ai_governance_session_row(id: 4, namespace: subgroup, user: owner,
        session_started_at: reference_time - 4.hours).merge(workflow_id: nil)
    end

    let(:duplicated_duo_event) do
      audit_event_row(workflow_id: project_duo_session[:workflow_id],
        created_at: project_duo_session[:session_started_at] + 1.minute)
    end

    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            aiGovernanceSessions(first: 10) {
              nodes { id auditEventsCount }
            }
          }
        }
      GRAPHQL
    end

    def counts_by_session
      sessions['nodes'].to_h { |node| node.values_at('id', 'auditEventsCount') }
    end

    before do
      insert_ai_governance_sessions(duo_session_without_workflow)

      clickhouse_fixture(:ai_audit_events, [
        duplicated_duo_event,
        duplicated_duo_event,
        audit_event_row(workflow_id: project_duo_session[:workflow_id],
          created_at: project_duo_session[:session_started_at] + 2.minutes),
        audit_event_row(ai_governance_session_id: external_session[:id],
          created_at: external_session[:session_started_at] + 1.minute),
        audit_event_row(ai_governance_session_id: external_session[:id],
          created_at: external_session[:session_started_at] - 1.day - 1.minute),
        # Shares its number with the external session's ID, but belongs to a workflow.
        audit_event_row(workflow_id: external_session[:id],
          created_at: external_session[:session_started_at] + 1.minute)
      ])
    end

    it 'counts the events of each session with one query per session kind', :aggregate_failures do
      expect(::AuditEvents::AiAuditEvents::ClickHouseFinder).to receive(:counts_for_workflows).once.and_call_original
      expect(::AuditEvents::AiAuditEvents::ClickHouseFinder).to receive(:counts_for_sessions).once.and_call_original

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(counts_by_session).to eq(
        gid(external_session) => 1,
        gid(namespace_duo_session) => 0,
        gid(project_duo_session) => 2,
        gid(duo_session_without_workflow) => 0
      )
    end
  end

  describe 'link fields' do
    # A chat workflow of another user: :read_agent_artifacts on the group doesn't grant :read_duo_workflow on it.
    let_it_be(:workflow) { create(:duo_workflows_workflow, :agentic_chat, project: project) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: owner) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }
    let_it_be(:issue_note) { create(:note_on_issue, project: project) }
    let_it_be(:work_item) { create(:work_item, project: project) }

    let_it_be(:merge_request_links) do
      %i[source created].map do |link_type|
        create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: merge_request,
          link_type: link_type)
      end
    end

    let_it_be(:note_links) do
      %i[triggered created].map do |link_type|
        create(:duo_workflows_workflow_note, workflow: workflow, note: issue_note, link_type: link_type)
      end
    end

    let_it_be(:work_item_links) do
      %i[source created].map do |link_type|
        create(:duo_workflows_workflow_work_item, workflow: workflow, work_item: work_item, link_type: link_type)
      end
    end

    let(:project_duo_session) do
      ai_governance_session_row(id: 1, namespace: project.project_namespace, project: project, user: owner,
        flow_type: 'chat', session_started_at: reference_time - 3.hours).merge(workflow_id: workflow.id)
    end

    let(:namespace_duo_session) do
      ai_governance_session_row(id: 2, namespace: subgroup, user: owner, flow_type: 'agentic_chat',
        session_started_at: reference_time - 2.hours).merge(workflow_id: other_workflow.id)
    end

    let(:query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            aiGovernanceSessions(first: 10) {
              nodes {
                id
                mergeRequestLinks { nodes { id linkType mergeRequest { id } } }
                noteLinks { nodes { id linkType note { id } } }
                workItemLinks { nodes { id linkType workItem { id } } }
              }
            }
          }
        }
      GRAPHQL
    end

    let(:no_links) { { 'mergeRequestLinks' => [], 'noteLinks' => [], 'workItemLinks' => [] } }

    before_all do
      # Guests can't read merge requests of private projects.
      project.add_reporter(owner)
    end

    def links_by_session
      sessions['nodes'].to_h do |node|
        [node['id'], node.slice('mergeRequestLinks', 'noteLinks', 'workItemLinks').transform_values { |v| v['nodes'] }]
      end
    end

    def expected_links(links, item_field, item)
      links.map do |link|
        { 'id' => global_id_of(link).to_s, 'linkType' => link.link_type.upcase,
          item_field => item && { 'id' => global_id_of(item).to_s } }
      end
    end

    it 'returns the links of each GitLab Duo session and none for an external session', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(links_by_session).to eq(
        gid(external_session) => no_links,
        gid(namespace_duo_session) => no_links,
        gid(project_duo_session) => {
          'mergeRequestLinks' => expected_links(merge_request_links, 'mergeRequest', merge_request),
          'noteLinks' => expected_links(note_links, 'note', issue_note),
          'workItemLinks' => expected_links(work_item_links, 'workItem', work_item)
        }
      )
    end

    it 'does not require read_duo_workflow on the workflow', :aggregate_failures do
      expect(current_user.can?(:read_duo_workflow, workflow)).to be(false)

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(links_by_session[gid(project_duo_session)]['mergeRequestLinks'])
        .to eq(expected_links(merge_request_links, 'mergeRequest', merge_request))
    end

    context 'when the user cannot read a linked item' do
      let_it_be(:hidden_merge_request) { create(:merge_request, source_project: create(:project, :private)) }
      let_it_be(:hidden_link) do
        create(:duo_workflows_workflow_merge_request, workflow: other_workflow, merge_request: hidden_merge_request)
      end

      it 'returns the link with a null item' do
        post_graphql(query, current_user: current_user)

        expect(links_by_session[gid(namespace_duo_session)]['mergeRequestLinks'])
          .to eq(expected_links([hidden_link], 'mergeRequest', nil))
      end
    end

    it 'avoids N+1 queries' do
      post_graphql(query, current_user: current_user)
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      extra_workflow = create(:duo_workflows_workflow, project: project, user: owner)
      create(:duo_workflows_workflow_merge_request, workflow: extra_workflow,
        merge_request: create(:merge_request, source_project: project, source_branch: 'extra'))
      create(:duo_workflows_workflow_note, workflow: extra_workflow, note: create(:note_on_issue, project: project))
      create(:duo_workflows_workflow_work_item, workflow: extra_workflow,
        work_item: create(:work_item, project: project))

      insert_ai_governance_sessions(
        ai_governance_session_row(id: 4, namespace: project.project_namespace, project: project, user: owner,
          session_started_at: reference_time - 4.hours).merge(workflow_id: extra_workflow.id),
        ai_governance_session_row(id: 5, namespace: group, user: owner, source: :claude_code_compliance_api,
          session_started_at: reference_time - 5.hours)
      )

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end
  end
end
