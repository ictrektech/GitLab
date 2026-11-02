# frozen_string_literal: true

require 'spec_helper'

# Based on ee/spec/requests/api/epics_spec.rb
# Should follow closely in order to ensure all situations are covered
RSpec.describe 'Query.group.mergeRequests', feature_category: :code_review_workflow do
  include GraphqlHelpers

  let_it_be(:group)     { create(:group) }
  let_it_be(:sub_group) { create(:group, parent: group) }

  let_it_be(:project_a) { create(:project, group: group) }
  let_it_be(:project_b) { create(:project, group: group) }
  let_it_be(:project_c) { create(:project, group: sub_group) }
  let_it_be(:project_x) { create(:project) }
  let_it_be(:user)      { create(:user, developer_of: [project_x, group]) }

  let_it_be(:archived_project) { create(:project, :archived, group: group) }
  let_it_be(:archived_mr) { create(:merge_request, source_project: archived_project) }

  let_it_be(:mr_attrs) do
    { target_branch: 'master' }
  end

  let_it_be(:mr_traits) do
    [:unique_branches, :unique_author]
  end

  let_it_be_with_reload(:mrs_a) { create_list(:merge_request, 2, *mr_traits, **mr_attrs, source_project: project_a) }
  let_it_be_with_reload(:mrs_b) { create_list(:merge_request, 2, *mr_traits, **mr_attrs, source_project: project_b) }
  let_it_be_with_reload(:mrs_c) { create_list(:merge_request, 2, *mr_traits, **mr_attrs, source_project: project_c) }
  let_it_be(:other_mr) { create(:merge_request, source_project: project_x) }

  let(:mrs_data) { graphql_data_at(:group, :merge_requests, :nodes) }

  def expected_mrs(mrs)
    mrs.map { |mr| a_graphql_entity_for(mr) }
  end

  describe 'not passing any arguments' do
    let(:query) do
      <<~GQL
      query($path: ID!) {
        group(fullPath: $path) {
          mergeRequests { nodes { id } }
        }
      }
      GQL
    end

    it 'can find all merge requests in the group, excluding sub-groups' do
      post_graphql(query, current_user: user, variables: { path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs(mrs_a + mrs_b))
    end
  end

  describe 'restricting by author' do
    let(:query) do
      <<~GQL
      query($path: ID!, $user: String) {
        group(fullPath: $path) {
          mergeRequests(authorUsername: $user) { nodes { id author { username } } }
        }
      }
      GQL
    end

    let(:author) { mrs_b.first.author }

    it 'can find all merge requests with user as author' do
      post_graphql(query, current_user: user, variables: { user: author.username, path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs([mrs_b.first]))
    end
  end

  describe 'restricting by assignee' do
    let(:query) do
      <<~GQL
      query($path: ID!, $user: String) {
        group(fullPath: $path) {
          mergeRequests(assigneeUsername: $user) { nodes { id } }
        }
      }
      GQL
    end

    let_it_be(:assignee) { create(:user) }

    before_all do
      mrs_b.second.assignees << assignee
      mrs_a.first.assignees << assignee
    end

    it 'can find all merge requests assigned to user' do
      post_graphql(query, current_user: user, variables: { user: assignee.username, path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs([mrs_a.first, mrs_b.second]))
    end
  end

  context 'when filtering by reviewer' do
    let(:query) do
      <<~GQL
      query($path: ID!, $user: String) {
        group(fullPath: $path) {
          mergeRequests(reviewerUsername: $user) { nodes { id } }
        }
      }
      GQL
    end

    let_it_be(:reviewer) { create(:user) }

    before do
      mrs_a.first.reviewers << reviewer
    end

    it 'returns all merge requests assigned to reviewer' do
      post_graphql(query, current_user: user, variables: { user: reviewer.username, path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs([mrs_a.first]))
    end
  end

  describe 'passing include_subgroups: true' do
    let(:query) do
      <<~GQL
      query($path: ID!) {
        group(fullPath: $path) {
          mergeRequests(includeSubgroups: true) { nodes { id } }
        }
      }
      GQL
    end

    it 'can find all merge requests in the group, including sub-groups' do
      post_graphql(query, current_user: user, variables: { path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs(mrs_a + mrs_b + mrs_c))
    end
  end

  describe 'passing include_archived: true' do
    let(:query) do
      <<~GQL
      query($path: ID!) {
        group(fullPath: $path) {
          mergeRequests(includeArchived: true) { nodes { id } }
        }
      }
      GQL
    end

    it 'can find all merge requests in the group, including from archived projects' do
      post_graphql(query, current_user: user, variables: { path: group.full_path })

      expect(mrs_data).to match_array(expected_mrs(mrs_a + mrs_b + [archived_mr]))
    end
  end

  describe 'timeLimitedCount' do
    let(:query) do
      <<~GQL
      query($path: ID!) {
        group(fullPath: $path) {
          mergeRequests(includeSubgroups: true) { timeLimitedCount }
        }
      }
      GQL
    end

    it 'returns the exact count without a time limit' do
      expect(ApplicationRecord).not_to receive(:with_fast_read_statement_timeout)

      post_graphql(query, current_user: user, variables: { path: group.full_path })

      expect(graphql_data_at(:group, :merge_requests, :time_limited_count)).to eq(6)
    end
  end

  describe 'N+1 queries', :use_sql_query_cache do
    let(:query) do
      <<~GQL
      query($path: ID!) {
        group(fullPath: $path) {
          mergeRequests(includeSubgroups: true) { nodes { id project { id fullPath } } }
        }
      }
      GQL
    end

    def post_query
      post_graphql(query, current_user: current_user, variables: { path: root_group.full_path })
    end

    shared_examples 'avoids N+1 queries when authorizing projects' do
      it 'does not add queries for each new project' do
        post_query # warm-up
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }
        expected_count = graphql_data_at(:group, :merge_requests, :nodes).size

        2.times do
          subgroup = create(:group, visibility, parent: root_group)
          create(:merge_request, source_project: create(:project, visibility, group: subgroup))
        end

        expect { post_query }.not_to exceed_all_query_limit(control)
        expect(graphql_data_at(:group, :merge_requests, :nodes).size).to eq(expected_count + 2)
      end
    end

    context 'with public projects and a non-member user' do
      let_it_be(:root_group) { create(:group, :public) }
      let_it_be(:current_user) { create(:user) }
      let(:visibility) { :public }

      before_all do
        create(:merge_request, source_project: create(:project, :public, group: root_group))
      end

      it_behaves_like 'avoids N+1 queries when authorizing projects'
    end

    context 'with private projects and a member user' do
      let(:root_group) { group }
      let(:current_user) { user }
      let(:visibility) { :private }

      it_behaves_like 'avoids N+1 queries when authorizing projects'
    end
  end
end
