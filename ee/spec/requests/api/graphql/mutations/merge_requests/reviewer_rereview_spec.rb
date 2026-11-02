# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Re-requesting a review of a merge request', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let(:current_user) { create(:user) }
  let(:user) { create(:user) }
  let(:merge_request) { create(:merge_request, reviewers: [user]) }
  let(:project) { merge_request.project }

  let(:input) { { user_id: global_id_of(user) } }

  let(:mutation) do
    graphql_mutation(
      :merge_request_reviewer_rereview,
      { project_path: project.full_path, iid: merge_request.iid.to_s }.merge(input),
      'errors'
    )
  end

  before do
    project.add_developer(current_user)
    project.add_developer(user)
  end

  it 'passes no depth to the service' do
    expect(MergeRequests::RequestReviewService).to receive(:new)
      .with(project: project, current_user: current_user, params: {})
      .and_call_original

    post_graphql_mutation(mutation, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect(graphql_mutation_response(:merge_request_reviewer_rereview)['errors']).to be_empty
  end

  context 'with a Duo Code Review depth' do
    let(:input) { { user_id: global_id_of(user), duo_code_review_depth: 'DEEP' } }

    it 'passes the depth to the service' do
      expect(MergeRequests::RequestReviewService).to receive(:new)
        .with(project: project, current_user: current_user, params: { duo_code_review_depth: 'deep' })
        .and_call_original

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_mutation_response(:merge_request_reviewer_rereview)['errors']).to be_empty
    end
  end

  context 'with an unknown depth' do
    let(:input) { { user_id: global_id_of(user), duo_code_review_depth: 'SHALLOW' } }

    it 'returns an error' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to be_present
    end
  end
end
