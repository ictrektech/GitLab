# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.orbit.serviceStatus', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:query) do
    graphql_query_for(:orbit, {}, query_graphql_field(:service_status, {}, 'state version components { name state }'))
  end

  let(:cluster_health) do
    {
      status: 'degraded',
      timestamp: '2026-10-25T12:00:00Z',
      version: '0.128.0',
      components: [
        { name: 'clickhouse', status: 'healthy', replicas: { ready: 1, desired: 1 }, metrics: {} },
        { name: 'indexer', status: 'unhealthy', replicas: { ready: 0, desired: 2 }, metrics: {} }
      ]
    }
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:get_cluster_health).and_return(cluster_health)
  end

  it 'returns the overall state, the version, and the state of each component' do
    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :service_status)).to eq(
      'state' => 'DEGRADED',
      'version' => '0.128.0',
      'components' => [
        { 'name' => 'clickhouse', 'state' => 'HEALTHY' },
        { 'name' => 'indexer', 'state' => 'UNHEALTHY' }
      ]
    )
  end

  it 'asks Orbit for the cluster health as the current user' do
    post_graphql(query, current_user: current_user, headers: { 'User-Agent' => 'TestAgent/1.0' })

    expect(grpc_client).to have_received(:get_cluster_health).with(
      user: current_user,
      request_context: having_attributes(user_agent: 'TestAgent/1.0')
    )
  end

  it 'returns the unknown state without components when Orbit is unreachable' do
    allow(grpc_client).to receive(:get_cluster_health).and_return({ status: 'unknown', error: 'Service unreachable' })

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :service_status)).to eq('state' => 'UNKNOWN', 'version' => nil, 'components' => [])
  end

  it 'returns the same status to an ai_workflows token as to the session' do
    post_graphql(query, current_user: current_user)
    session_status = graphql_data_at(:orbit, :service_status)
    expect(session_status).to be_present
    token = create(:oauth_access_token, user: current_user, scopes: [:ai_workflows, :mcp])

    post_graphql(query, token: { oauth_access_token: token })

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :service_status)).to eq(session_status)
  end

  describe 'granular token authorization' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
      let(:user) { current_user }
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  it 'returns no status and makes no gRPC call when the Orbit license is not available' do
    stub_licensed_features(orbit: false)

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :service_status)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  context 'with an instance license but no trial or purchase' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(orbit_promo_access_gate: true)
    end

    it 'returns the status' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit, :service_status, :state)).to eq('DEGRADED')
    end
  end

  it 'returns no status and makes no gRPC call when Orbit is not configured' do
    stub_config(knowledge_graph: { 'enabled' => false })

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :service_status)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  it 'asks Orbit once when the query selects the status more than once' do
    fields = 'first: serviceStatus { state } second: serviceStatus { state }'

    post_graphql(graphql_query_for(:orbit, {}, fields), current_user: current_user)

    expect_graphql_errors_to_include('"serviceStatus" field can be requested only for 1 Orbit(s) at a time.')
    expect(grpc_client).to have_received(:get_cluster_health).once
  end

  context 'when the Orbit authorization header cannot be built' do
    before do
      allow(grpc_client).to receive(:get_cluster_health).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::AuthorizationError, 'boom'
      )
    end

    it 'returns an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include('Orbit request failed')
    end
  end
end
