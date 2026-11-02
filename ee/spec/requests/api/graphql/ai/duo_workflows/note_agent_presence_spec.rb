# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Note.agentPresence', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:other_member) { create(:user, developer_of: project) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:catalog_item) { create(:ai_catalog_item, :agent, project: project, name: 'Developer Agent') }
  let_it_be(:catalog_item_version) { catalog_item.latest_version }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, ai_catalog_item_version: catalog_item_version,
      source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
  end

  let_it_be_with_reload(:note) { create(:note, project: project, noteable: issue) }

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
        flowTrigger { description }
        user { id username }
        userPermissions { readDuoWorkflow }
      }
    GRAPHQL
  end

  let(:query) { graphql_query_for(:note, { id: note.to_gid }, fields) }

  before do
    stub_feature_flags(agent_presence_consolidation: group)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
  end

  subject(:agent_presence) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:note, :agent_presence)
  end

  it 'is null when no session posted the note' do
    expect(agent_presence).to be_nil
    expect(graphql_errors).to be_nil
  end

  context 'when a session posted the note through the API' do
    before do
      create(:duo_workflows_workflow_note, workflow: workflow, note: note, link_type: :created)
    end

    it 'returns the actor line data' do
      expect(agent_presence).to eq(
        'sessionId' => workflow.to_gid.to_s,
        'agentName' => 'Developer Agent',
        'agentCatalogWebPath' => "/explore/ai-catalog/agents/#{catalog_item.id}",
        'sourceType' => 'SLACK',
        'sourceLink' => 'https://slack.com/archives/C123/p456',
        'triggerSource' => 'HUMAN',
        'flowTrigger' => nil,
        'user' => { 'id' => user.to_gid.to_s, 'username' => user.username },
        'userPermissions' => { 'readDuoWorkflow' => true }
      )
    end

    context 'when a schedule started the session' do
      let_it_be(:service_account) { create(:user, :service_account, developer_of: project) }
      let_it_be(:scheduled_workflow) do
        create(:duo_workflows_workflow, project: project, user: service_account, trigger_source: :scheduled)
      end

      let_it_be(:scheduled_note) { create(:note, project: project, noteable: issue) }
      let(:query) { graphql_query_for(:note, { id: scheduled_note.to_gid }, fields) }

      before do
        create(:duo_workflows_workflow_note, workflow: scheduled_workflow, note: scheduled_note, link_type: :created)
      end

      it 'reports the automation that started the session' do
        expect(agent_presence).to include('triggerSource' => 'SCHEDULED')
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
      let_it_be(:public_project) { create(:project, :public, group: group) }
      let_it_be(:public_issue) { create(:issue, project: public_project) }
      let_it_be(:public_note) { create(:note, project: public_project, noteable: public_issue) }
      let_it_be(:public_workflow) do
        create(:duo_workflows_workflow, project: public_project, user: user,
          source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
      end

      let(:current_user) { nil }
      let(:query) { graphql_query_for(:note, { id: public_note.to_gid }, fields) }

      before do
        create(:duo_workflows_workflow_note, workflow: public_workflow, note: public_note, link_type: :created)
      end

      it 'returns the presence to anonymous viewers of a readable note' do
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

  context 'when the session is private to its invoker' do
    let_it_be(:slack_workflow) do
      create(:duo_workflows_workflow, project: project, user: user,
        messaging_callback_context: { 'adapter' => 'slack' },
        source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
    end

    let(:current_user) { other_member }

    before do
      create(:duo_workflows_workflow_note, workflow: slack_workflow, note: note, link_type: :created)
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
      create(:duo_workflows_workflow_note, workflow: triggered_workflow, note: note, link_type: :created)
    end

    it 'returns the trigger and the user the trigger ran as' do
      expect(agent_presence).to include(
        'sessionId' => triggered_workflow.to_gid.to_s,
        'flowTrigger' => { 'description' => flow_trigger.description },
        'user' => { 'id' => user.to_gid.to_s, 'username' => user.username }
      )
    end

    context 'when the viewer cannot read the trigger' do
      let(:current_user) { create(:user, reporter_of: project) }

      it 'returns a null trigger' do
        expect(agent_presence).to include('sessionId' => triggered_workflow.to_gid.to_s, 'flowTrigger' => nil)
      end
    end
  end

  context 'when the session has no recorded source' do
    let_it_be(:unsourced_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

    before do
      create(:duo_workflows_workflow_note, workflow: unsourced_workflow, note: note, link_type: :created)
    end

    it 'returns null source fields' do
      expect(agent_presence).to include('sourceType' => nil, 'sourceLink' => nil)
    end
  end

  describe 'granular PAT authorization' do
    let_it_be(:link) { create(:duo_workflows_workflow_note, workflow: workflow, note: note, link_type: :created) }

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type', :read_note do
      let(:boundary_object) { project }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
      let(:skipped_data_path) { [:note, :agent_presence] }
    end
  end

  describe 'across a list of notes' do
    let(:list_query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            issue(iid: "#{issue.iid}") {
              notes { nodes { id #{fields} } }
            }
          }
        }
      GRAPHQL
    end

    it 'does not issue queries per note' do
      link_session_to(create(:note, project: project, noteable: issue), session: workflow)
      link_session_to(create(:note, project: project, noteable: issue))
      post_graphql(list_query, current_user: other_member)

      control = ActiveRecord::QueryRecorder.new { post_graphql(list_query, current_user: other_member) }

      4.times { link_session_to(create(:note, project: project, noteable: issue)) }

      expect { post_graphql(list_query, current_user: other_member) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:project, :issue, :notes, :nodes).pluck('agentPresence').compact.size).to eq(6)
    end

    # Group-level notes have no project, so the flag actor comes from the note's namespace.
    # Counts cached queries too, so a per-note namespace load would show up here.
    context 'on a group-level work item' do
      let_it_be(:group_member) { create(:user, developer_of: group) }
      let_it_be(:work_item) { create(:work_item, :group_level, namespace: group) }

      let(:list_query) do
        <<~GRAPHQL
          query {
            namespace(fullPath: "#{group.full_path}") {
              workItem(iid: "#{work_item.iid}") {
                widgets {
                  ... on WorkItemWidgetNotes {
                    notes { nodes { id #{fields} } }
                  }
                }
              }
            }
          }
        GRAPHQL
      end

      before do
        stub_licensed_features(epics: true)
      end

      it 'does not issue queries per note' do
        link_session_to(create(:note, project: nil, noteable: work_item), session: workflow)
        link_session_to(create(:note, project: nil, noteable: work_item))
        post_graphql(list_query, current_user: group_member)

        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          post_graphql(list_query, current_user: group_member)
        end

        3.times { link_session_to(create(:note, project: nil, noteable: work_item)) }

        expect { post_graphql(list_query, current_user: group_member) }.not_to exceed_all_query_limit(control)

        notes = graphql_data_at(:namespace, :work_item, :widgets).pluck('notes').compact.first['nodes']
        expect(notes.pluck('agentPresence').compact.size).to eq(5)
      end
    end

    def link_session_to(new_note, session: nil)
      session ||= create(:duo_workflows_workflow, project: project, user: create(:user, developer_of: project),
        ai_catalog_item_version: catalog_item_version)
      create(:duo_workflows_workflow_note, workflow: session, note: new_note, link_type: :created)
    end
  end
end
