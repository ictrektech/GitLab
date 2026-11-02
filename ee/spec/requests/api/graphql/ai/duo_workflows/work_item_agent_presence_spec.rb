# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WorkItem.agentPresence', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:other_member) { create(:user, developer_of: project) }
  let_it_be(:catalog_item) { create(:ai_catalog_item, :agent, project: project, name: 'Developer Agent') }
  let_it_be(:catalog_item_version) { catalog_item.latest_version }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, ai_catalog_item_version: catalog_item_version,
      source_type: :slack, source_link: 'https://slack.com/archives/C123/p456')
  end

  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:group_member) { create(:user, developer_of: group) }

  # read_duo_workflow needs :duo_workflow on the container, which reads the viewer's
  # Duo seat off the User the request authenticates, so give each viewer a real one.
  let_it_be(:add_on_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :self_managed) }

  let(:current_user) { user }
  let(:fields) do
    <<~GRAPHQL
      agentPresence {
        sessionId
        agentName
        agentCatalogWebPath
        sourceType
        sourceLink
        user { id username }
        userPermissions { readDuoWorkflow }
      }
    GRAPHQL
  end

  let(:query) do
    <<~GRAPHQL
      query {
        namespace(fullPath: "#{project.full_path}") {
          workItem(iid: "#{work_item.iid}") { #{fields} }
        }
      }
    GRAPHQL
  end

  before_all do
    [user, other_member, group_member].each do |seat_holder|
      create(:gitlab_subscription_user_add_on_assignment, user: seat_holder, add_on_purchase: add_on_purchase)
    end
  end

  before do
    stub_feature_flags(agent_presence_consolidation: group)
    stub_licensed_features(ai_features: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
  end

  subject(:agent_presence) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:namespace, :work_item, :agent_presence)
  end

  def link_session(session, item, link_type)
    create(:duo_workflows_workflow_work_item, workflow: session, work_item: item, project: session.project,
      namespace: session.namespace, link_type: link_type)
  end

  context 'when no session is linked to the work item' do
    it 'is null' do
      expect(agent_presence).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a session only started from the work item' do
    before do
      link_session(workflow, work_item, :source)
    end

    it 'is null' do
      expect(agent_presence).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when a session created the work item' do
    before do
      link_session(workflow, work_item, :created)
    end

    it 'returns the actor line data' do
      expect(agent_presence).to eq(
        'sessionId' => workflow.to_gid.to_s,
        'agentName' => 'Developer Agent',
        'agentCatalogWebPath' => "/explore/ai-catalog/agents/#{catalog_item.id}",
        'sourceType' => 'SLACK',
        'sourceLink' => 'https://slack.com/archives/C123/p456',
        'user' => { 'id' => user.to_gid.to_s, 'username' => user.username },
        'userPermissions' => { 'readDuoWorkflow' => true }
      )
    end

    context 'when the same session also started from the work item' do
      before do
        link_session(workflow, work_item, :source)
      end

      it 'returns the presence for the created link' do
        expect(agent_presence).to include('sessionId' => workflow.to_gid.to_s)
      end
    end

    context 'when another session also created the work item later' do
      let_it_be(:later_workflow) { create(:duo_workflows_workflow, project: project, user: other_member) }

      before do
        link_session(later_workflow, work_item, :created)
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
      create(:duo_workflows_workflow, project: project, user: user, source_type: :slack,
        source_link: 'https://slack.com/archives/C123/p456', messaging_callback_context: { 'adapter' => 'slack' })
    end

    let(:current_user) { other_member }

    before do
      link_session(slack_workflow, work_item, :created)
    end

    it 'returns the presence but keeps the session unreadable' do
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
      link_session(triggered_workflow, work_item, :created)
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
      link_session(unsourced_workflow, work_item, :created)
    end

    it 'returns null source fields' do
      expect(agent_presence).to include('sourceType' => nil, 'sourceLink' => nil)
    end
  end

  context 'on a group-level work item' do
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }
    let_it_be(:group_workflow) do
      create(:duo_workflows_workflow, project: nil, namespace: group, user: group_member)
    end

    let(:current_user) { group_member }
    let(:query) do
      <<~GRAPHQL
        query {
          namespace(fullPath: "#{group.full_path}") {
            workItem(iid: "#{group_work_item.iid}") { #{fields} }
          }
        }
      GRAPHQL
    end

    before do
      stub_licensed_features(epics: true)
      link_session(group_workflow, group_work_item, :created)
    end

    it 'resolves the presence from the namespace-scoped session' do
      expect(agent_presence).to include('sessionId' => group_workflow.to_gid.to_s)
      expect(graphql_errors).to be_nil
    end
  end

  describe 'across a list of work items' do
    let(:list_query) do
      <<~GRAPHQL
        query {
          project(fullPath: "#{project.full_path}") {
            workItems { nodes { id #{fields} } }
          }
        }
      GRAPHQL
    end

    def create_session_work_item
      session = create(:duo_workflows_workflow, project: project, user: user,
        ai_catalog_item_version: catalog_item_version)
      item = create(:work_item, project: project)
      link_session(session, item, :created)
    end

    it 'stays at two link/workflow queries regardless of the number of work items' do
      create_session_work_item
      create(:work_item, project: project)
      post_graphql(list_query, current_user: other_member)

      control = ActiveRecord::QueryRecorder.new { post_graphql(list_query, current_user: other_member) }

      3.times { create_session_work_item }

      expect { post_graphql(list_query, current_user: other_member) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:project, :work_items, :nodes).pluck('agentPresence').compact.size).to eq(4)
    end
  end

  describe 'across work items in different top-level groups' do
    # The feature flag actor is each work item's root namespace, and `sourceLink` and
    # `userPermissions.readDuoWorkflow` evaluate the session policy against each session's
    # project. The policy preload leaves one query per distinct session project: the
    # `duo_features_enabled` cascade's locked-ancestor lookup on `namespace_settings`, which
    # no preloader batches. The control has two roots so the preload's fixed cost is already paid.
    def session_work_item_in_new_root
      root = create(:group)
      item_project = create(:project, group: create(:group, parent: root), developers: user)
      session = create(:duo_workflows_workflow, project: item_project, user: user,
        ai_catalog_item_version: catalog_item_version)
      item = create(:work_item, project: item_project)
      link_session(session, item, :created)
      item
    end

    def reference_query(items, with_presence:)
      refs = items.map { |item| "#{item.project.full_path}##{item.iid}" }
      presence = with_presence ? fields : ''

      <<~GRAPHQL
        query {
          workItemsByReference(contextNamespacePath: "#{project.full_path}", refs: #{refs.to_json}) {
            nodes { id #{presence} }
          }
        }
      GRAPHQL
    end

    def presence_query_count(items)
      without = ActiveRecord::QueryRecorder.new do
        post_graphql(reference_query(items, with_presence: false), current_user: user)
      end
      with = ActiveRecord::QueryRecorder.new do
        post_graphql(reference_query(items, with_presence: true), current_user: user)
      end

      with.count - without.count
    end

    before do
      # The three-root request runs just over 100 queries on self-managed and 110 on SaaS; lift
      # the per-request cap so it completes, and pin the per-root delta instead, as other heavy
      # request specs do.
      allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(120)
    end

    shared_examples 'a fixed query cost per extra root namespace' do
      it 'adds the per-root queries once for each extra root namespace' do
        stub_feature_flags(agent_presence_consolidation: true)
        items = Array.new(2) { session_work_item_in_new_root }
        post_graphql(reference_query(items, with_presence: true), current_user: user)

        control = presence_query_count(items)

        items << session_work_item_in_new_root

        expect(presence_query_count(items)).to eq(control + queries_per_extra_root)
        expect(graphql_data_at(:work_items_by_reference, :nodes).pluck('agentPresence').compact.size).to eq(3)
      end
    end

    it_behaves_like 'a fixed query cost per extra root namespace' do
      let(:queries_per_extra_root) { 1 }
    end

    # SaaS checks Duo access through each root namespace: `User#authorized_root_namespace?`
    # runs `Group#member_of_self_or_descendant?` per root (memoized by root id only), on top
    # of the cascade lookup self-managed pays.
    context 'on SaaS', :saas do
      let(:queries_per_extra_root) { 2 }

      it_behaves_like 'a fixed query cost per extra root namespace'
    end
  end

  describe 'the work item frontend query' do
    let(:query) { get_graphql_query_as_string('work_items/graphql/work_item_by_iid.query.graphql') }
    let(:variables) { { fullPath: project.full_path, iid: work_item.iid.to_s } }

    before do
      link_session(workflow, work_item, :created)
    end

    it 'executes without errors with the flag enabled' do
      post_graphql(query, current_user: current_user, variables: variables)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:namespace, :work_item, :id)).to eq(work_item.to_gid.to_s)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agent_presence_consolidation: false)
      end

      it 'executes without errors' do
        post_graphql(query, current_user: current_user, variables: variables)

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:namespace, :work_item, :id)).to eq(work_item.to_gid.to_s)
      end
    end
  end
end
