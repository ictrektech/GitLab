# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session <-> note links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:public_project) { create(:project, :public) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # All notes of a project hang off one noteable so the N+1 checks isolate the link
  # resolver rather than the per-noteable authorization each distinct note loads.
  let_it_be(:noteable, freeze: false) { create(:issue, project: project) }
  let_it_be(:public_noteable, freeze: false) { create(:issue, project: public_project) }

  # The note we start the traversal from, and a second one the session created.
  let_it_be(:source_artifact) { create_artifact(project) }
  let_it_be(:other_artifact) { create_artifact(project) }

  def create_artifact(project)
    create(:note, project: project, noteable: project == public_project ? public_noteable : noteable)
  end

  it_behaves_like 'a GraphQL API for Duo Agent Platform session links', artifact: :note, source_link_type: :created

  describe 'duoTriggeredSession' do
    let(:current_user) { user }

    before do
      # Make read_duo_workflow pass for the workflow owner, matching WorkflowPolicy's
      # owner rule. The link type delegates to the workflow for the same ability.
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
    end

    context 'when querying the triggered session' do
      let_it_be(:catalog_item_version) { create(:ai_catalog_item_version) }
      let_it_be(:triggered_workflow) do
        create(:duo_workflows_workflow, project: project, user: user, ai_catalog_item_version: catalog_item_version)
      end

      let_it_be(:triggered_link) do
        create(:duo_workflows_workflow_note, workflow: triggered_workflow, note: source_artifact,
          link_type: :triggered)
      end

      let(:session_fields) { 'duoTriggeredSession { id agentName statusName }' }
      let(:query) do
        <<~GRAPHQL
          query {
            note(id: "#{source_artifact.to_gid}") {
              #{session_fields}
            }
          }
        GRAPHQL
      end

      it 'returns the triggered session', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(:note, :duo_triggered_session)).to eq(
          'id' => triggered_workflow.to_gid.to_s,
          'agentName' => catalog_item_version.item.name,
          'statusName' => triggered_workflow.status_name.to_s
        )
      end

      it 'does not N+1 when resolving catalog agent names for multiple notes' do
        post_graphql(query, current_user: current_user)
        control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

        other_note = create_artifact(project)
        other_item_version = create(:ai_catalog_item_version)
        # A different owner on purpose: WorkflowPolicy loads workflow.user to deny
        # access, so a shared owner hides the N+1 behind the query cache.
        other_workflow = create(:duo_workflows_workflow,
          project: project, user: create(:user, developer_of: project),
          ai_catalog_item_version: other_item_version)
        create(:duo_workflows_workflow_note, workflow: other_workflow, note: other_note, link_type: :triggered)

        multi_note_query = <<~GRAPHQL
          query {
            first: note(id: "#{source_artifact.to_gid}") { #{session_fields} }
            second: note(id: "#{other_note.to_gid}") { #{session_fields} }
          }
        GRAPHQL

        expect do
          post_graphql(multi_note_query, current_user: current_user)
        end.not_to exceed_query_limit(control)
      end
    end

    describe 'granular personal access token authorization' do
      # A public project lets the token pass the parent NoteType authorization via the
      # public-access bypass, so the test gates on the field's `read_duo_workflow`
      # permission at the user boundary.
      let_it_be(:public_note) { create_artifact(public_project) }
      let_it_be(:public_workflow) { create(:duo_workflows_workflow, project: public_project, user: user) }

      let_it_be(:public_triggered_link) do
        create(:duo_workflows_workflow_note, workflow: public_workflow, note: public_note, link_type: :triggered)
      end

      let(:query) { graphql_query_for(:note, { id: public_note.to_gid }, 'duoTriggeredSession { id }') }

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(public_project, :duo_workflow).and_return(true)
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
        let(:boundary_object) { :user }
        let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
      end
    end
  end
end
