# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.orbit.schema', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:fields) do
    <<~FIELDS
      nodes {
        nodes {
          name
          description
          domain { name }
          primaryKey
          labelProperty
          properties { nodes { name dataType nullable enumValues } }
          display { color size }
        }
      }
      edges {
        nodes {
          name
          description
          endpoints { nodes { source { name } target { name } } }
        }
      }
    FIELDS
  end

  let(:query) { graphql_query_for(:orbit, {}, query_graphql_field(:schema, {}, fields)) }
  let(:schema) do
    {
      schema_version: '0.1',
      domains: [{ name: 'code_review', description: 'Code review.', node_names: ['MergeRequest'] }],
      nodes: [
        {
          name: 'MergeRequest',
          domain: 'code_review',
          description: 'A merge request.',
          primary_key: 'id',
          label_field: 'title',
          properties: [
            { name: 'id', data_type: 'int64', nullable: false, enum_values: [] },
            { name: 'state', data_type: 'enum', nullable: false, enum_values: %w[opened merged] }
          ],
          style: { size: 28, color: '#F59E0B' },
          outgoing_edges: [],
          incoming_edges: ['AUTHORED']
        },
        { name: 'User', domain: 'core', description: 'A user.', primary_key: 'id', label_field: 'username' }
      ],
      edges: [
        {
          name: 'AUTHORED',
          description: 'Authorship.',
          variants: [
            { source_type: 'User', target_type: 'MergeRequest' },
            { source_type: 'User', target_type: 'Vulnerability' }
          ]
        }
      ]
    }
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })

    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:get_graph_schema).and_return(schema)
  end

  it 'returns every node kind and edge kind with its details' do
    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :schema)).to eq(
      'nodes' => {
        'nodes' => [
          {
            'name' => 'MergeRequest',
            'description' => 'A merge request.',
            'domain' => { 'name' => 'code_review' },
            'primaryKey' => 'id',
            'labelProperty' => 'title',
            'properties' => {
              'nodes' => [
                { 'name' => 'id', 'dataType' => 'int64', 'nullable' => false, 'enumValues' => [] },
                { 'name' => 'state', 'dataType' => 'enum', 'nullable' => false, 'enumValues' => %w[opened merged] }
              ]
            },
            'display' => { 'color' => '#F59E0B', 'size' => 28 }
          },
          {
            'name' => 'User',
            'description' => 'A user.',
            'domain' => { 'name' => 'core' },
            'primaryKey' => 'id',
            'labelProperty' => 'username',
            'properties' => { 'nodes' => [] },
            'display' => nil
          }
        ]
      },
      'edges' => {
        'nodes' => [
          {
            'name' => 'AUTHORED',
            'description' => 'Authorship.',
            'endpoints' => {
              'nodes' => [{ 'source' => { 'name' => 'User' }, 'target' => { 'name' => 'MergeRequest' } }]
            }
          }
        ]
      }
    )
  end

  it 'returns the same schema to an ai_workflows token as to the session' do
    post_graphql(query, current_user: current_user)
    session_schema = graphql_data_at(:orbit, :schema)
    expect(session_schema).to be_present
    token = create(:oauth_access_token, user: current_user, scopes: [:ai_workflows, :mcp])

    post_graphql(query, token: { oauth_access_token: token })

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :schema)).to eq(session_schema)
  end

  describe 'granular token authorization' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_orbit do
      let(:user) { current_user }
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  it 'asks Orbit for the details of every node kind as the current user' do
    post_graphql(query, current_user: current_user)

    expect(grpc_client).to have_received(:get_graph_schema).with(
      user: current_user,
      expand_nodes: ['*'],
      request_context: an_instance_of(Analytics::KnowledgeGraph::RequestContext)
    )
  end

  it 'returns no schema and makes no gRPC call when the Orbit license is not available' do
    stub_licensed_features(orbit: false)

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :schema)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  it 'returns no schema and makes no gRPC call when Orbit is not configured' do
    stub_config(knowledge_graph: { 'enabled' => false })

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :schema)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  it 'returns no Orbit data and makes no gRPC call when the user is not signed in' do
    post_graphql(query, current_user: nil)

    expect(graphql_data_at(:orbit)).to be_nil
    expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:new)
  end

  it 'asks Orbit once when the query selects the schema more than once' do
    fields = 'first: schema { nodes { nodes { name } } } second: schema { nodes { nodes { name } } }'

    post_graphql(graphql_query_for(:orbit, {}, fields), current_user: current_user)

    expect_graphql_errors_to_include('"schema" field can be requested only for 1 Orbit(s) at a time.')
    expect(grpc_client).to have_received(:get_graph_schema).once
  end

  it 'returns no schema when Orbit returns no schema content' do
    allow(grpc_client).to receive(:get_graph_schema).and_return({})

    post_graphql(query, current_user: current_user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:orbit, :schema)).to be_nil
  end

  context 'when the Orbit server does not have the RPC' do
    before do
      allow(grpc_client).to receive(:get_graph_schema).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'boom', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )
    end

    it 'returns no schema without an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:orbit, :schema)).to be_nil
    end
  end

  context 'when the gRPC call fails' do
    before do
      allow(grpc_client).to receive(:get_graph_schema).and_raise(
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

  context 'when the Orbit authorization header cannot be built' do
    before do
      allow(grpc_client).to receive(:get_graph_schema).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::AuthorizationError, 'boom'
      )
    end

    it 'returns an error' do
      post_graphql(query, current_user: current_user)

      expect_graphql_errors_to_include('Orbit request failed')
    end
  end
end
