# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization.securityTrackedContextQuota', :with_current_organization,
  feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:organization_user, :owner, organization: current_organization).user }

  let(:query_param) { { 'id' => current_organization.to_gid } }
  let(:query) do
    graphql_query_for('organization', query_param,
      'securityTrackedContextQuota { limit usage remaining explicitlySet }')
  end

  before do
    ::Organizations::OrganizationSetting.for(current_organization.id)
      .update!(security_tracked_context_quota: 5)
  end

  it 'returns the quota information for the organization', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    expect(response).to have_gitlab_http_status(:success)
    expect_graphql_errors_to_be_empty

    quota = graphql_data_at(:organization, :security_tracked_context_quota)
    expect(quota).to include(
      'limit' => 5,
      'usage' => 0,
      'remaining' => 5,
      'explicitlySet' => true
    )
  end

  context 'when no quota is set and no default applies' do
    before do
      ::Organizations::OrganizationSetting.for(current_organization.id)
        .update!(security_tracked_context_quota: nil)
    end

    it 'returns null for limit and remaining', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:organization, :security_tracked_context_quota)).to include(
        'limit' => nil,
        'usage' => 0,
        'remaining' => nil,
        'explicitlySet' => false
      )
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_organization do
    let(:user) { current_user }
    let(:object) { current_organization }
    let(:boundary_object) { :instance }
    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
  end

  context 'when the user is not an organization admin' do
    let_it_be(:member) { create(:organization_user, organization: current_organization).user }

    it 'returns nil for the quota field but still resolves the organization', :aggregate_failures do
      post_graphql(query, current_user: member)

      expect(response).to have_gitlab_http_status(:success)
      expect_graphql_errors_to_be_empty

      expect(graphql_data_at(:organization)).to be_present
      expect(graphql_data_at(:organization, :security_tracked_context_quota)).to be_nil
    end
  end

  context 'when the user cannot read the organization' do
    let_it_be(:private_organization) { create(:organization, :private) }
    let_it_be(:non_member) { create(:user) }

    let(:query_param) { { 'id' => private_organization.to_gid } }

    it 'does not return the organization' do
      post_graphql(query, current_user: non_member)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_data_at(:organization)).to be_nil
    end
  end
end
