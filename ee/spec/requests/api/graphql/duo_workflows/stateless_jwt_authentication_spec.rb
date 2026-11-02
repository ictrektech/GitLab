# frozen_string_literal: true

require 'spec_helper'

# A composite-identity stateless JWT, presented as a Bearer header the way the
# duo-workflow-service headless executor does, authenticates as the embedded human.
RSpec.describe 'GraphQL API authenticated with a composite-identity stateless JWT',
  feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
  let_it_be(:organization) { create(:organization) }
  let_it_be(:human_user) { create(:user, organizations: [organization]) }
  let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

  let(:query) { graphql_query_for('currentUser', {}, %w[id username]) }

  before do
    stub_feature_flags(duo_workflow_use_token_issuer: [human_user, service_account])

    # CachingKeyLoader memoizes Keys.current at the class level, which leaks
    # across specs when other specs also create keys. Pin it to ours.
    allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
    allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
  end

  def mint_jwt
    result = ::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService.new(
      current_user: human_user,
      organization: organization,
      service_account: service_account
    ).execute

    expect(result).to be_success

    token = result[:oauth_access_token].plaintext_token
    # The service silently falls back to an OAuth token without the flag or a
    # signing key, and that token would pass both examples too.
    expect(::Authn::Tokens::StatelessAccessToken.from_jwt(token)).to be_present

    token
  end

  it 'authenticates as the embedded human, not the service account subject' do
    jwt = mint_jwt

    post_graphql(query, current_user: nil, headers: { 'Authorization' => "Bearer #{jwt}" })

    expect(response).to have_gitlab_http_status(:ok)
    expect(graphql_data.dig('currentUser', 'username')).to eq(human_user.username)
  end

  it 'rejects the token once revoked', :aggregate_failures do
    jwt = mint_jwt
    headers = { 'Authorization' => "Bearer #{jwt}" }

    post_graphql(query, current_user: nil, headers: headers)
    expect(response).to have_gitlab_http_status(:ok)
    expect(graphql_data.dig('currentUser', 'username')).to eq(human_user.username)

    revoke_result = ::Ai::DuoWorkflows::RevokeTokenService.new(token: jwt, current_user: human_user).execute
    expect(revoke_result[:status]).to eq(:success)

    post_graphql(query, current_user: nil, headers: headers)

    expect(graphql_errors).to include(a_hash_including('message' => 'Invalid token'))
  end
end
