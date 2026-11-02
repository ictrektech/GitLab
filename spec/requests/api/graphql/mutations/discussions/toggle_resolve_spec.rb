# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Toggling the resolve status of a discussion', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:noteable) { create(:merge_request, source_project: project) }

  let(:discussion) do
    create(:diff_note_on_merge_request, noteable: noteable, project: project).to_discussion
  end

  let(:mutation) do
    graphql_mutation(:discussion_toggle_resolve, { id: discussion.to_global_id.to_s, resolve: true })
  end

  let(:mutation_response) { graphql_mutation_response(:discussion_toggle_resolve) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_note do
    let(:user) { create(:user, developer_of: project) }
    let(:boundary_object) { project }
    let(:request) do
      post_graphql_mutation(
        graphql_mutation(:discussion_toggle_resolve, { id: discussion.to_global_id.to_s, resolve: true }, 'errors'),
        token: { personal_access_token: pat }
      )
    end
  end

  context 'when the user does not have permission' do
    let_it_be(:current_user) { create(:user) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when user has permission' do
    let_it_be(:current_user) { create(:user, developer_of: project) }

    it 'returns the discussion without errors', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response).to include(
        'discussion' => be_present,
        'errors' => be_empty
      )
    end

    context 'when an error is encountered' do
      before do
        allow_next_instance_of(::Discussions::ResolveService) do |service|
          allow(service).to receive(:execute).and_raise(ActiveRecord::RecordNotSaved)
        end
      end

      it_behaves_like 'a mutation that returns errors in the response',
        errors: ['Discussion failed to be resolved']
    end

    context 'when one request toggles more threads than the rate limit', :clean_gitlab_redis_rate_limiting do
      let(:other_discussion) do
        create(:diff_note_on_merge_request, noteable: noteable, project: project).to_discussion
      end

      let(:query) do
        <<~GQL
          mutation {
            first: discussionToggleResolve(input: { id: "#{discussion.to_global_id}", resolve: true }) { errors }
            second: discussionToggleResolve(input: { id: "#{other_discussion.to_global_id}", resolve: true }) { errors }
          }
        GQL
      end

      before do
        stub_application_setting(discussions_resolve_limit: 1)
      end

      it 'stops at the limit and returns too many requests', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(discussion.first_note.reload).to be_resolved
        expect(other_discussion.first_note.reload).not_to be_resolved
      end
    end
  end
end
