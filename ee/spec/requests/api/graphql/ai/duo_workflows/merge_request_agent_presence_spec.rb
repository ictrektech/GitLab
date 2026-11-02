# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MergeRequest.agentPresence', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:other_member) { create(:user, developer_of: project) }
  let_it_be(:catalog_item) { create(:ai_catalog_item, :agent, project: project, name: 'Developer Agent') }
  let_it_be(:catalog_item_version) { catalog_item.latest_version }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, ai_catalog_item_version: catalog_item_version,
      source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
  end

  let_it_be(:merge_request) { create(:merge_request, source_project: project) }

  let(:current_user) { user }
  let(:fields) do
    <<~GRAPHQL
      agentPresence {
        sessionId
        agentName
        agentCatalogWebPath
        sourceType
        sourceLink
        triggerSource
        user { id username }
        userPermissions { readDuoWorkflow }
      }
    GRAPHQL
  end

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path },
      query_graphql_field(:merge_request, { iid: merge_request.iid.to_s }, fields))
  end

  before do
    stub_feature_flags(agent_presence_consolidation: group)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
  end

  subject(:agent_presence) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:project, :merge_request, :agent_presence)
  end

  def link_session(session, item, link_type)
    create(:duo_workflows_workflow_merge_request, workflow: session, merge_request: item, project: session.project,
      link_type: link_type)
  end

  it 'is null when no session is linked to the merge request' do
    expect(agent_presence).to be_nil
    expect(graphql_errors).to be_nil
  end

  context 'when a session only started from the merge request' do
    before do
      link_session(workflow, merge_request, :source)
    end

    it 'is null' do
      expect(agent_presence).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a session created the merge request' do
    before do
      link_session(workflow, merge_request, :created)
    end

    it 'returns the actor line data' do
      expect(agent_presence).to eq(
        'sessionId' => workflow.to_gid.to_s,
        'agentName' => 'Developer Agent',
        'agentCatalogWebPath' => "/explore/ai-catalog/agents/#{catalog_item.id}",
        'sourceType' => 'SLACK',
        'sourceLink' => 'https://slack.com/archives/C123/p456',
        'triggerSource' => 'HUMAN',
        'user' => { 'id' => user.to_gid.to_s, 'username' => user.username },
        'userPermissions' => { 'readDuoWorkflow' => true }
      )
    end

    context 'when the same session also started from the merge request' do
      before do
        link_session(workflow, merge_request, :source)
      end

      it 'returns the presence for the created link' do
        expect(agent_presence).to include('sessionId' => workflow.to_gid.to_s)
      end
    end

    context 'when another session also created the merge request later' do
      let_it_be(:later_workflow) { create(:duo_workflows_workflow, project: project, user: other_member) }

      before do
        link_session(later_workflow, merge_request, :created)
      end

      it 'returns the oldest created link' do
        expect(agent_presence['sessionId']).to eq(workflow.to_gid.to_s)
      end
    end

    context 'when the viewer cannot read the session' do
      let(:current_user) { other_member }

      it 'still returns the presence but reports the session as not readable' do
        expect(agent_presence).to include(
          'sessionId' => workflow.to_gid.to_s,
          'agentName' => 'Developer Agent',
          'sourceType' => 'SLACK',
          'sourceLink' => nil,
          'userPermissions' => { 'readDuoWorkflow' => false }
        )
      end
    end

    context 'when there is no current user' do
      let_it_be(:public_project) { create(:project, :public, :repository, group: group) }
      let_it_be(:public_merge_request) { create(:merge_request, source_project: public_project) }
      let_it_be(:public_workflow) do
        create(:duo_workflows_workflow, project: public_project, user: user,
          source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
      end

      let(:current_user) { nil }
      let(:query) do
        graphql_query_for(:project, { full_path: public_project.full_path },
          query_graphql_field(:merge_request, { iid: public_merge_request.iid.to_s }, fields))
      end

      before do
        link_session(public_workflow, public_merge_request, :created)
      end

      it 'returns the presence to anonymous viewers of a readable merge request' do
        expect(agent_presence).to include(
          'sessionId' => public_workflow.to_gid.to_s,
          'sourceType' => 'SLACK',
          'sourceLink' => nil,
          'userPermissions' => { 'readDuoWorkflow' => false }
        )
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agent_presence_consolidation: false)
      end

      it 'is null' do
        expect(agent_presence).to be_nil
      end
    end
  end

  context 'when a schedule started the session' do
    let_it_be(:service_account) { create(:user, :service_account, developer_of: project) }
    let_it_be(:scheduled_workflow) do
      create(:duo_workflows_workflow, project: project, user: service_account, trigger_source: :scheduled)
    end

    before do
      link_session(scheduled_workflow, merge_request, :created)
    end

    it 'reports the automation that started the session' do
      expect(agent_presence).to include(
        'triggerSource' => 'SCHEDULED',
        'user' => { 'id' => service_account.to_gid.to_s, 'username' => service_account.username }
      )
    end
  end

  context 'when the session is private to its invoker' do
    let_it_be(:slack_workflow) do
      create(:duo_workflows_workflow, project: project, user: user,
        messaging_callback_context: { 'adapter' => 'slack' },
        source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
    end

    let(:current_user) { other_member }

    before do
      link_session(slack_workflow, merge_request, :created)
    end

    it 'returns the presence but keeps the session and its source link unreadable' do
      expect(agent_presence).to include(
        'sessionId' => slack_workflow.to_gid.to_s,
        'sourceType' => 'SLACK',
        'sourceLink' => nil,
        'userPermissions' => { 'readDuoWorkflow' => false }
      )
    end
  end

  context 'when a flow trigger started the session' do
    let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }
    let_it_be(:triggered_workflow) do
      create(:duo_workflows_workflow, project: project, user: user, trigger_source: :system,
        trigger_flow_trigger: flow_trigger)
    end

    let(:current_user) { other_member }

    before do
      link_session(triggered_workflow, merge_request, :created)
    end

    it 'returns the user the trigger ran as' do
      expect(agent_presence).to include(
        'sessionId' => triggered_workflow.to_gid.to_s,
        'user' => { 'id' => user.to_gid.to_s, 'username' => user.username }
      )
    end
  end

  context 'when the session has no recorded source' do
    let_it_be(:unsourced_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

    before do
      link_session(unsourced_workflow, merge_request, :created)
    end

    it 'returns null source fields' do
      expect(agent_presence).to include('sourceType' => nil, 'sourceLink' => nil)
    end
  end

  describe 'granular PAT authorization' do
    let_it_be(:link) do
      create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: merge_request,
        link_type: :created)
    end

    # Root query, so the token only needs the merge request permission and not read_project as well.
    let(:query) { graphql_query_for(:merge_request, { id: merge_request.to_gid }, fields) }

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_merge_request do
      let(:boundary_object) { project }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
      let(:skipped_data_path) { [:merge_request, :agent_presence] }
    end
  end

  describe 'across a list of merge requests' do
    let_it_be(:subgroup_project) { create(:project, :repository, group: create(:group, parent: group)) }
    let_it_be(:group_member) { create(:user, developer_of: group) }

    let(:list_query) do
      <<~GRAPHQL
        query {
          group(fullPath: "#{group.full_path}") {
            mergeRequests(includeSubgroups: true) { nodes { id #{fields} } }
          }
        }
      GRAPHQL
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(subgroup_project, :duo_workflow).and_return(true)
    end

    def create_session_merge_request(session: nil, target: project)
      session ||= create(:duo_workflows_workflow, project: target, user: create(:user, developer_of: target),
        ai_catalog_item_version: catalog_item_version)
      link_session(session, create(:merge_request, source_project: target, source_branch: generate(:branch)), :created)
    end

    it 'keeps the query count constant as merge requests are added' do
      create_session_merge_request(session: workflow)
      create_session_merge_request(target: subgroup_project)
      post_graphql(list_query, current_user: group_member)

      control = ActiveRecord::QueryRecorder.new { post_graphql(list_query, current_user: group_member) }

      2.times { create_session_merge_request }
      create_session_merge_request(target: subgroup_project)

      expect { post_graphql(list_query, current_user: group_member) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:group, :merge_requests, :nodes).pluck('agentPresence').compact.size).to eq(5)
    end
  end
end
