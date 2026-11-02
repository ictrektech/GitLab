# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.orbit.queryTemplates', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:query) { graphql_query_for(:orbit, {}, query_graphql_field(:query_templates, {}, 'name description query')) }
  let(:templates) do
    [
      { name: 'my_mrs', description: 'My merge requests.', raw_query: 'MATCH (mr:MergeRequest) RETURN mr.title' }
    ]
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:list_named_queries).and_return(templates)
  end

  it 'returns each template with its GQL text' do
    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :query_templates)).to eq(
      [
        { 'name' => 'my_mrs', 'description' => 'My merge requests.',
          'query' => 'MATCH (mr:MergeRequest) RETURN mr.title' }
      ]
    )
  end

  it 'asks Orbit for the templates as the current user' do
    post_graphql(query, current_user: current_user, headers: { 'User-Agent' => 'TestAgent/1.0' })

    expect(grpc_client).to have_received(:list_named_queries).with(
      user: current_user,
      request_context: having_attributes(user_agent: 'TestAgent/1.0')
    )
  end

  it 'returns the same templates to an ai_workflows token as to the session' do
    post_graphql(query, current_user: current_user)
    session_templates = graphql_data_at(:orbit, :query_templates)
    expect(session_templates).to be_present
    token = create(:oauth_access_token, user: current_user, scopes: [:ai_workflows, :mcp])

    post_graphql(query, token: { oauth_access_token: token })

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :query_templates)).to eq(session_templates)
  end

  describe 'granular token authorization' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
      let(:user) { current_user }
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  it 'returns no templates and makes no gRPC call when the Orbit license is not available' do
    stub_licensed_features(orbit: false)

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :query_templates)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  context 'with an instance license but no trial or purchase' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(orbit_promo_access_gate: true)
    end

    it 'returns no templates and makes no gRPC call' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit, :query_templates)).to be_nil
      expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
    end
  end

  it 'returns no templates and makes no gRPC call when Orbit is not configured' do
    stub_config(knowledge_graph: { 'enabled' => false })

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :query_templates)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  it 'asks Orbit once when the query selects the templates more than once' do
    fields = 'first: queryTemplates { name } second: queryTemplates { name }'

    post_graphql(graphql_query_for(:orbit, {}, fields), current_user: current_user)

    expect_graphql_errors_to_include('"queryTemplates" field can be requested only for 1 Orbit(s) at a time.')
    expect(grpc_client).to have_received(:list_named_queries).once
  end

  context 'when the Orbit server does not have the RPC' do
    before do
      allow(grpc_client).to receive(:list_named_queries).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'boom', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )
    end

    it 'returns no templates without an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit, :query_templates)).to eq([])
    end
  end

  context 'when the gRPC call fails' do
    before do
      allow(grpc_client).to receive(:list_named_queries).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'boom', grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
        )
      )
    end

    it 'returns an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include('Orbit request failed')
    end
  end
end
