# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Updating a group-level note', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be_with_reload(:epic) { create(:epic, group: group) }
  let_it_be_with_reload(:note) { create(:note, project: nil, noteable: epic, author: user) }
  let(:mutation) do
    graphql_mutation(:update_note, { id: global_id_of(note).to_s, body: 'updated' }, 'errors')
  end

  before do
    stub_licensed_features(epics: true)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_note do
    let(:boundary_object) { group }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  describe 'quick actions added to a merge request note' do
    let_it_be(:project) { create(:project, :repository, developers: user) }
    let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project, author: user) }
    let_it_be_with_reload(:mr_note) { create(:note, project: project, noteable: merge_request, author: user) }
    let_it_be(:label) { create(:label, project: project, title: 'bug') }

    let(:scopes) { [:ai_workflows] }

    def update_note(body)
      token = create(:oauth_access_token, user: user, scopes: scopes)
      mutation = graphql_mutation(:update_note, { id: global_id_of(mr_note).to_s, body: body }, 'errors')

      post_graphql_mutation(mutation, token: { oauth_access_token: token })
    end

    context 'with an ai_workflows token' do
      it 'rejects a quick action that is not allowed for AI workflows', :aggregate_failures do
        expect { update_note("Updated\n/close") }.not_to change { mr_note.reload.note }

        expect(graphql_errors).to contain_exactly(
          a_hash_including('message' => 'Quick actions close cannot be used with AI workflows.')
        )
        expect(merge_request.reload).to be_opened
      end

      it 'does not run a quick action that acts while it is interpreted', :aggregate_failures do
        pipeline_service = instance_double(MergeRequests::CreatePipelineService, allowed?: true)
        allow(MergeRequests::CreatePipelineService).to receive(:new).and_return(pipeline_service)
        expect(pipeline_service).not_to receive(:execute_async)

        update_note("Updated\n/run_pipeline")

        expect(graphql_errors).to contain_exactly(
          a_hash_including('message' => 'Quick actions run_pipeline cannot be used with AI workflows.')
        )
      end

      it 'applies an allowed quick action', :aggregate_failures do
        update_note("Updated\n/label ~bug")

        expect(graphql_errors).to be_nil
        expect(merge_request.reload.labels).to contain_exactly(label)
      end
    end

    context 'with an api token' do
      let(:scopes) { [:api] }

      it 'applies the quick action' do
        update_note("Updated\n/close")

        expect(merge_request.reload).to be_closed
      end
    end

    context 'without any attribute to update' do
      it 'does not update the note', :aggregate_failures do
        expect(Gitlab::UsageDataCounters::MergeRequestActivityUniqueCounter).not_to receive(:track_edit_comment_action)

        mutation = graphql_mutation(:update_note, { id: global_id_of(mr_note).to_s }, 'errors')
        post_graphql_mutation(mutation, current_user: user)

        expect(graphql_errors).to be_nil
      end
    end
  end
end
