# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Usage quotas pipelines Integration (GraphQL fixtures)', type: :request,
  feature_category: :consumables_cost_management do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers
  include Ci::MinutesHelpers
  include SubscriptionPortalHelpers

  let_it_be(:user, freeze: false) { create(:user, :with_namespace) }
  let_it_be(:namespace, freeze: false) { user.namespace }

  before do
    create_list(:project, 3, :with_ci_minutes, amount_used: 5, namespace: namespace)
    set_ci_minutes_used(namespace, 300)
    sign_in(user)
  end

  base_input_path = 'usage_quotas/pipelines/namespace/graphql/queries/'
  base_output_path = 'graphql/usage_quotas/pipelines/integration/'

  describe GraphQL::Query do
    it "#{base_output_path}get_namespace_ci_minutes_usage.query.graphql.json" do
      query = get_graphql_query_as_string("#{base_input_path}namespace_ci_minutes_usage.query.graphql", ee: true)

      post_graphql(query, current_user: user, variables: { namespaceId: nil })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_projects_ci_minutes_usage.query.graphql.json" do
      query = get_graphql_query_as_string("#{base_input_path}projects_ci_minutes_usage.query.graphql", ee: true)

      post_graphql(query, current_user: user, variables: {
        namespaceId: nil,
        first: 20,
        date: Date.current.beginning_of_month.iso8601
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:ci_minutes_project_monthly_usage, :nodes).size).to eq(3)
    end

    it "#{base_output_path}get_subscription_permissions_data.query.graphql.json" do
      stub_saas_features(cdot_graphql_proxy: true)
      stub_signing_key
      stub_full_request(graphql_url, method: :post)
        .with(body: /getSubscriptionPermissionsData/)
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
          data: {
            subscription: { canAddSeats: true, canAddDuoProSeats: true, canRenew: true, communityPlan: false },
            userActionAccess: { limitedAccessReason: nil }
          }
        }.to_json)

      # CustomersDot queries are not in the GitLab schema, so the query finder skips them.
      query = File.read(Rails.root.join(
        'ee/app/assets/javascripts/fulfillment/shared_queries/subscription_actions_reason.customer.query.graphql'
      ))

      post '/-/customers_dot/proxy/graphql',
        params: { operationName: 'getSubscriptionPermissionsData', variables: { namespaceId: namespace.id },
                  query: query }.to_json,
        headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to be_successful
    end
  end
end
