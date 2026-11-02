# frozen_string_literal: true

require 'spec_helper'

# Does not use 'a GraphQL API for Duo Agent Platform session links': that shared example
# traverses artifact -> `duoWorkflowLinks` -> session, but here the artifact is itself a
# session, reached through `duoWorkflowWorkflows` with no reverse field.
RSpec.describe 'Duo Agent Platform session <-> session links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:source_workflow) { create(:duo_workflows_workflow, project: project, user: user) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  let_it_be(:link) do
    create(:duo_workflows_workflow_workflow, workflow: workflow, linked_workflow: source_workflow, link_type: :source)
  end

  let(:current_user) { user }
  let(:filter) { nil }
  let(:query) do
    <<~GRAPHQL
      query {
        duoWorkflowWorkflows(workflowId: "#{workflow.to_global_id}") {
          nodes {
            id
            workflowLinks#{filter && "(linkType: #{filter})"} {
              nodes {
                linkType
                createdAt
                workflow { id }
                linkedWorkflow { id }
              }
            }
          }
        }
      }
    GRAPHQL
  end

  def workflow_links
    graphql_data_at(:duo_workflow_workflows, :nodes, 0, :workflow_links, :nodes)
  end

  before do
    stub_licensed_features(ai_workflows: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    # The seat is read off the user the request authenticates, which is loaded from the
    # database rather than being the record built here.
    allow_next_found_instance_of(User) do |found_user|
      allow(found_user).to receive(:allowed_to_use?).and_return(true)
    end
  end

  it 'returns the sessions linked to the session' do
    post_graphql(query, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_errors).to be_nil
    expect(workflow_links).to contain_exactly(
      a_hash_including(
        'linkType' => 'SOURCE',
        'workflow' => { 'id' => workflow.to_global_id.to_s },
        'linkedWorkflow' => { 'id' => source_workflow.to_global_id.to_s }
      )
    )
  end

  context 'with a link_type filter' do
    let(:filter) { 'SOURCE' }

    it 'returns the links of the requested type' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(workflow_links.pluck('linkType')).to contain_exactly('SOURCE')
    end
  end

  context 'when the session has no linked sessions' do
    let_it_be(:lonely_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

    let(:query) do
      graphql_query_for(:duo_workflow_workflows, { workflow_id: lonely_workflow.to_global_id.to_s },
        'nodes { workflowLinks { nodes { linkType } } }')
    end

    it 'returns an empty list of links' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(workflow_links).to be_empty
    end
  end

  context 'when the user cannot read the linked session' do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: other_user) }

    let_it_be(:redacted_link) do
      create(:duo_workflows_workflow_workflow, workflow: workflow, linked_workflow: other_workflow)
    end

    it 'returns the link but redacts the unreadable session' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(workflow_links.pluck('linkedWorkflow')).to contain_exactly(
        { 'id' => source_workflow.to_global_id.to_s }, nil
      )
    end
  end

  describe 'inverseWorkflowLinks' do
    let(:query) do
      <<~GRAPHQL
        query {
          duoWorkflowWorkflows(workflowId: "#{source_workflow.to_global_id}") {
            nodes {
              inverseWorkflowLinks {
                nodes {
                  linkType
                  workflow { id }
                  linkedWorkflow { id }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    def inverse_links
      graphql_data_at(:duo_workflow_workflows, :nodes, 0, :inverse_workflow_links, :nodes)
    end

    it 'returns the sessions that link to the session' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(inverse_links).to contain_exactly(
        'linkType' => 'SOURCE',
        'workflow' => { 'id' => workflow.to_global_id.to_s },
        'linkedWorkflow' => { 'id' => source_workflow.to_global_id.to_s }
      )
    end

    context 'when the user cannot read the linking session' do
      let_it_be(:other_user) { create(:user, developer_of: project) }
      let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: other_user) }

      let_it_be(:unreadable_link) do
        create(:duo_workflows_workflow_workflow, workflow: other_workflow, linked_workflow: source_workflow)
      end

      # The link policy delegates to `workflow`, which is the other session here, so
      # the whole link drops out rather than being returned with a redacted side.
      it 'omits the link' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(inverse_links.pluck('workflow')).to contain_exactly('id' => workflow.to_global_id.to_s)
      end
    end

    it 'does not N+1 on the linking sessions' do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      extra_workflow = create(:duo_workflows_workflow, project: project, user: user)
      create(:duo_workflows_workflow_workflow, workflow: extra_workflow, linked_workflow: source_workflow)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      expect(inverse_links.count).to eq(2)
    end
  end

  context 'with multiple linked sessions' do
    it 'does not N+1 on the linked sessions' do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      extra_workflow = create(:duo_workflows_workflow, project: project, user: user)
      create(:duo_workflows_workflow_workflow, workflow: workflow, linked_workflow: extra_workflow)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      expect(workflow_links.count).to eq(2)
    end
  end

  describe 'granular personal access token authorization' do
    let(:pat_query) do
      <<~GRAPHQL
        query {
          duoWorkflowWorkflows(ids: ["#{workflow.to_global_id}"]) {
            nodes {
              workflowLinks {
                nodes { linkType }
              }
            }
          }
        }
      GRAPHQL
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(pat_query, token: { personal_access_token: pat }) }
    end
  end
end
