# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Home panel Integration (GraphQL fixtures)', type: :request,
  feature_category: :groups_and_projects do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:group) { create(:group, :public) }
  let_it_be(:project) { create(:project, :public, group: group) }

  let_it_be(:non_member) { create(:user) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:group_developer) { create(:user) }
  let_it_be(:group_maintainer) { create(:user) }

  before_all do
    project.add_developer(developer)
    project.add_maintainer(maintainer)
    group.add_developer(group_developer)
    group.add_maintainer(group_maintainer)
  end

  base_output_path = 'graphql/home_panel/integration/'
  project_query = 'graphql_shared/queries/get_project_by_path.graphql'
  star_mutation = 'stars/components/graphql/mutations/star.mutation.graphql'

  def user_permissions
    graphql_data.dig('project', 'userPermissions')
  end

  describe GraphQL::Query do
    # Each fixture is recorded as a different user because the actions dropdown
    # derives its items from userPermissions; the guards pin the permission
    # combination each variant exists to represent.
    it "#{base_output_path}get_project_by_path.query.graphql.json" do
      query = get_graphql_query_as_string(project_query)

      post_graphql(query, current_user: maintainer, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(user_permissions).to include('viewEditPage' => true, 'canLeave' => true)
    end

    it "#{base_output_path}get_project_by_path_developer.query.graphql.json" do
      query = get_graphql_query_as_string(project_query)

      post_graphql(query, current_user: developer, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(user_permissions).to include('viewEditPage' => false, 'canLeave' => true)
    end

    it "#{base_output_path}get_project_by_path_non_member.query.graphql.json" do
      query = get_graphql_query_as_string(project_query)

      post_graphql(query, current_user: non_member, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(user_permissions).to include('viewEditPage' => false, 'canLeave' => false)
    end

    it "#{base_output_path}get_project_by_path_group_developer.query.graphql.json" do
      query = get_graphql_query_as_string(project_query)

      post_graphql(query, current_user: group_developer, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      # Membership through the group is not direct, so the user cannot leave.
      expect(user_permissions).to include('viewEditPage' => false, 'canLeave' => false)
    end

    it "#{base_output_path}get_project_by_path_group_maintainer.query.graphql.json" do
      query = get_graphql_query_as_string(project_query)

      post_graphql(query, current_user: group_maintainer, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(user_permissions).to include('viewEditPage' => true, 'canLeave' => false)
    end
  end

  describe GraphQL::Query, 'mutations' do
    it "#{base_output_path}set_star_status.mutation.graphql.json" do
      mutation = get_graphql_query_as_string(star_mutation)

      post_graphql(mutation, current_user: developer,
        variables: { projectId: project.to_global_id.to_s, starred: true })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('starProject', 'count')).to eq('1')
    end

    it "#{base_output_path}set_star_status_unstar.mutation.graphql.json" do
      # Star first so the fixture records a real unstar, not a no-op (count is 0 either way).
      developer.toggle_star(project)
      mutation = get_graphql_query_as_string(star_mutation)

      post_graphql(mutation, current_user: developer,
        variables: { projectId: project.to_global_id.to_s, starred: false })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('starProject', 'count')).to eq('0')
    end
  end
end
