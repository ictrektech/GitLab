# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Timelogs', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:group) { create(:group, reporters: user) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user_project) { create(:project, reporters: user) }

  let_it_be_with_reload(:user_issue) { create(:issue, project: user_project) }
  let_it_be_with_reload(:group_issue) { create(:issue, project: create(:project, group: group)) }
  let_it_be_with_reload(:project_issue) { create(:issue, project: project) }

  let_it_be_with_reload(:user_timelog) { create(:timelog, user: user, issue: user_issue) }
  let_it_be_with_reload(:group_timelog) { create(:timelog, issue: group_issue) }
  let_it_be_with_reload(:project_timelog) { create(:timelog, issue: project_issue) }

  let(:params) { {} }
  let(:group_id) { "gid://gitlab/Group/#{group.id}" }
  let(:project_id) { "gid://gitlab/Project/#{project.id}" }
  let(:current_user) { user }

  subject(:execute_query) { post_graphql(query, current_user: current_user) }

  shared_examples 'an OK response with no errors' do
    it 'returns no error message' do
      execute_query

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil
    end
  end

  shared_examples 'a response containing the correct timelogs' do
    it 'returns the expected timelogs' do
      execute_query

      expect(graphql_data_at(:timelogs, :nodes).pluck('id')).to match_array(expected_timelogs)
    end
  end

  context 'with no parameters' do
    context 'when not an admin' do
      it 'returns an error message' do
        execute_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(graphql_errors).to contain_exactly(
          a_hash_including('message' => 'Non-admin users must provide a groupId, projectId, or current username')
        )
      end
    end

    context 'when an admin' do
      let!(:current_user) { create(:user, :admin) }

      it_behaves_like 'an OK response with no errors'
    end
  end

  context 'with group_id parameter' do
    let(:params) { { group_id: group_id } }
    let(:expected_timelogs) do
      [
        "gid://gitlab/Timelog/#{project_timelog.id}",
        "gid://gitlab/Timelog/#{group_timelog.id}"
      ]
    end

    it_behaves_like 'an OK response with no errors'
    it_behaves_like 'a response containing the correct timelogs'
  end

  context 'with project_id parameter' do
    let(:params) { { project_id: project_id } }
    let(:expected_timelogs) { ["gid://gitlab/Timelog/#{project_timelog.id}"] }

    it_behaves_like 'an OK response with no errors'
    it_behaves_like 'a response containing the correct timelogs'
  end

  context 'with username parameter' do
    context 'when current user' do
      let(:params) { { username: user.username } }
      let(:expected_timelogs) { ["gid://gitlab/Timelog/#{user_timelog.id}"] }

      it_behaves_like 'an OK response with no errors'
      it_behaves_like 'a response containing the correct timelogs'
    end

    context 'when not current user' do
      let(:params) { { username: 'username' } }

      it 'returns an error message' do
        execute_query

        expect(response).to have_gitlab_http_status(:ok)
        expect(graphql_errors).to contain_exactly(
          a_hash_including('message' => 'Non-admin users must provide a groupId, projectId, or current username')
        )
      end
    end
  end

  describe 'avoiding N+1 queries on timelog associations' do
    let_it_be(:nplus1_group) { create(:group, reporters: user) }

    let(:current_user) { user }
    let(:params) { { group_id: "gid://gitlab/Group/#{nplus1_group.id}" } }

    def full_query
      nodes = <<~NODE
        nodes {
          id
          timeSpent
          summary
          user { id }
          issue { id }
          mergeRequest { id }
          project { id }
        }
      NODE

      graphql_query_for(:timelogs, { **params }, nodes)
    end

    def seed_timelogs_across_projects(count)
      count.times do
        project = create(:project, group: nplus1_group)
        issue = create(:issue, project: project)
        create(:issue_timelog, issue: issue, user: user)
        merge_request = create(:merge_request, :skip_diff_creation, source_project: project)
        create(:merge_request_timelog, merge_request: merge_request, user: user)
      end
    end

    # TimelogResolver#preloads batch-loads the issue, merge_request and project
    # associations, so the number of SELECTs against those tables stays flat as the
    # number of timelogs grows. This guards that preload against regressing to a per-node load.
    #
    # The overall query count still scales with the number of distinct projects: TimelogType
    # authorizes every node with :read_issuable, which loads project_features, members and
    # project_group_links per project. That per-node authorization N+1 cannot be fixed by
    # preloading and is tracked as the batch-authorization follow-up in
    # https://gitlab.com/gitlab-org/gitlab/-/work_items/636078.
    it 'batch-loads the issuable and project associations as the number of timelogs grows' do
      seed_timelogs_across_projects(1)
      post_graphql(full_query, current_user: current_user) # warm up schema and request caches

      association_queries = ->(recorder) do
        recorder.log.count { |sql| sql.match?(/FROM "(issues|merge_requests)"/) }
      end

      control = ActiveRecord::QueryRecorder.new do
        post_graphql(full_query, current_user: current_user)
      end
      expect(graphql_data_at(:timelogs, :nodes).size).to eq(2)

      seed_timelogs_across_projects(3)

      scaled = ActiveRecord::QueryRecorder.new do
        post_graphql(full_query, current_user: current_user)
      end
      expect(graphql_data_at(:timelogs, :nodes).size).to eq(8)

      expect(association_queries.call(scaled)).to eq(association_queries.call(control))
    end
  end

  def query
    timelog_nodes = <<~NODE
      nodes {
        id
      }
    NODE

    graphql_query_for(
      :timelogs,
      { **params },
      timelog_nodes
    )
  end
end
