# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline subscriptions Integration (GraphQL fixtures)', type: :request, feature_category: :continuous_integration do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:namespace) { create(:group, name: 'frontend-fixtures', path: 'frontend-fixtures') }
  let_it_be(:group_one) { create(:group) }
  let_it_be(:group_two) { create(:group) }
  let_it_be(:project, freeze: false) do
    create(:project, :public, :repository, namespace: namespace, path: 'pipeline-subscriptions-project')
  end

  let_it_be(:upstream_project, freeze: false) { create(:project, :public, :repository, namespace: group_one) }
  let_it_be(:downstream_project, freeze: false) do
    create(:project, :public, :repository, upstream_projects: [project], namespace: group_two)
  end

  let_it_be(:user) { create(:user, maintainer_of: [project, upstream_project, downstream_project]) }

  base_output_path = 'graphql/ci/pipeline_subscriptions/integration/'
  graphql_path = 'ci/pipeline_subscriptions/graphql/'

  before do
    stub_licensed_features(ci_project_subscriptions: true)
  end

  describe GraphQL::Query do
    let(:upstream_query) do
      get_graphql_query_as_string("#{graphql_path}queries/get_upstream_subscriptions.query.graphql", ee: true)
    end

    let(:downstream_query) do
      get_graphql_query_as_string("#{graphql_path}queries/get_downstream_subscriptions.query.graphql", ee: true)
    end

    it "#{base_output_path}get_downstream_subscriptions.query.graphql.json" do
      post_graphql(downstream_query, current_user: user, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :ci_subscribed_projects, :count)).to eq(1)
    end

    it "#{base_output_path}get_upstream_subscriptions.query.graphql.json" do
      post_graphql(upstream_query, current_user: user, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :ci_subscriptions_projects, :count)).to eq(0)
    end

    it "#{base_output_path}get_upstream_subscriptions_subscribed.query.graphql.json" do
      create(:ci_subscriptions_project, downstream_project: project, upstream_project: upstream_project)

      post_graphql(upstream_query, current_user: user, variables: { fullPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :ci_subscriptions_projects, :count)).to eq(1)
    end
  end

  describe GraphQL::Query, 'mutations' do
    let(:add_mutation) do
      get_graphql_query_as_string("#{graphql_path}mutations/add_pipeline_subscription.mutation.graphql", ee: true)
    end

    let(:delete_mutation) do
      get_graphql_query_as_string("#{graphql_path}mutations/delete_pipeline_subscription.mutation.graphql", ee: true)
    end

    it "#{base_output_path}add_pipeline_subscription.mutation.graphql.json" do
      post_graphql(add_mutation, current_user: user, variables: {
        input: { projectPath: project.full_path, upstreamPath: upstream_project.full_path }
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_mutation_response(:project_subscription_create)['errors']).to eq([])
    end

    it "#{base_output_path}add_pipeline_subscription_not_found.mutation.graphql.json" do
      post_graphql(add_mutation, current_user: user, variables: {
        input: { projectPath: project.full_path, upstreamPath: 'wrong/path' }
      })

      expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
    end

    it "#{base_output_path}delete_pipeline_subscription.mutation.graphql.json" do
      subscription = create(:ci_subscriptions_project, downstream_project: project, upstream_project: upstream_project)

      post_graphql(delete_mutation, current_user: user, variables: { id: subscription.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
      expect(graphql_mutation_response(:project_subscription_delete)['errors']).to eq([])
    end
  end
end
