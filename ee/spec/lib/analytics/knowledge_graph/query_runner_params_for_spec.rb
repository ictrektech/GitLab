# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::QueryRunner, '.params_for', feature_category: :knowledge_graph do
  let(:user) { create(:user) }
  let(:query) { '{"nodes":["MergeRequest"]}' }
  let(:format) { :raw }
  let(:endpoint) { 'localhost:50054' }
  let(:jwt_token) { 'test-jwt-token' }
  let(:source_type) { 'rest' }
  let(:request_context) { Analytics::KnowledgeGraph::RequestContext.new(source_type: source_type) }

  subject(:params) do
    described_class.params_for(query: query, user: user, format: format, request_context: request_context)
  end

  before do
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive_messages(
      configured_endpoint: endpoint,
      outgoing_headers: { 'x-gitlab-enabled-instance-verbose-ai-logs' => 'false' }
    )
    allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
      .with(user: user, request_context: request_context)
      .and_return(jwt_token)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:secure_channel?).with(endpoint).and_return(false)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:private_address?).with(endpoint).and_return(true)
  end

  it 'builds the Orbit query params' do
    expect(params).to eq({
      'GkgServer' => {
        'address' => endpoint,
        'headers' => {
          'authorization' => "Bearer #{jwt_token}",
          'x-gitlab-enabled-instance-verbose-ai-logs' => 'false'
        }
      },
      'Query' => query,
      'Language' => 'gql',
      'Format' => format.to_s,
      'TimeoutSeconds' => 30
    })
  end

  context 'when on SaaS with gkg_verbose_logs flag enabled', :saas do
    before do
      stub_feature_flags(knowledge_graph_billing: false)
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:outgoing_headers).and_call_original
      stub_application_setting(enabled_instance_verbose_ai_logs: false)
    end

    it 'includes x-gitlab-enabled-feature-flags in headers' do
      expect(params.dig('GkgServer', 'headers')).to include(
        'x-gitlab-enabled-feature-flags' => 'verbose_gkg_logs'
      )
    end
  end

  context 'when instance verbose AI logs setting is enabled' do
    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:outgoing_headers).and_call_original
      stub_application_setting(enabled_instance_verbose_ai_logs: true)
    end

    it 'includes x-gitlab-enabled-instance-verbose-ai-logs in headers' do
      expect(params.dig('GkgServer', 'headers')).to include(
        'x-gitlab-enabled-instance-verbose-ai-logs' => 'true'
      )
    end
  end

  context 'when mcp_id is provided' do
    subject(:params) do
      described_class.params_for(query: query, user: user, format: format, mcp_id: 'mcp-123',
        request_context: request_context)
    end

    it 'includes McpId in the params' do
      expect(params).to include('McpId' => 'mcp-123')
    end
  end

  context 'when a governing namespace must be selected' do
    let(:governing_namespace_finder) do
      instance_double(
        Analytics::KnowledgeGraph::GoverningNamespaceFinder,
        candidates: create_list(:group, 2),
        single_candidate_fallback: nil
      )
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      allow(Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for)
        .and_return(governing_namespace_finder)
    end

    it 'raises before minting a JWT', :aggregate_failures do
      expect { params }.to raise_error(Analytics::KnowledgeGraph::GoverningNamespaceGuard::RequiredError)
      expect(Analytics::KnowledgeGraph::JwtAuth).not_to have_received(:generate_token)
    end
  end

  context 'when mcp_id is nil' do
    it 'does not include McpId in the params' do
      expect(params).not_to have_key('McpId')
    end
  end

  context 'when query_type is :named' do
    subject(:params) do
      described_class.params_for(query: query, user: user, format: format, query_type: :named,
        request_context: request_context)
    end

    it 'includes QueryType in the params' do
      expect(params).to include('QueryType' => 'named', 'Language' => 'gql')
    end
  end

  context 'when GQL is enabled' do
    let(:query) { " MATCH (u:User {name: 'Zoë \\\"雪\\\"'}) RETURN u LIMIT 1\n" }

    subject(:params) do
      described_class.params_for(query: query, user: user, format: :llm,
        mcp_id: 'gql-request', request_context: request_context)
    end

    it 'preserves the text and includes the language', :aggregate_failures do
      expect(params).to include('Query' => query, 'Language' => 'gql', 'Format' => 'llm')
      expect(params).not_to have_key('QueryType')
    end
  end

  context 'with a query language' do
    it 'sends that language' do
      gql_params = described_class.params_for(query: query, user: user, format: format, language: 'gql')

      expect(gql_params).to include('Language' => 'gql')
    end
  end

  context 'with a configured streaming timeout' do
    before do
      stub_config(knowledge_graph: { streaming_timeout_seconds: 45 })
    end

    it 'uses the configured timeout' do
      expect(params['TimeoutSeconds']).to eq(45)
    end
  end

  context 'with the streaming timeout set in the environment' do
    before do
      stub_env('KNOWLEDGE_GRAPH_STREAMING_TIMEOUT', '12')
    end

    it 'uses the environment value' do
      expect(params['TimeoutSeconds']).to eq(12)
    end
  end

  context 'when query_type is not provided' do
    it 'does not include QueryType in the params' do
      expect(params).not_to have_key('QueryType')
    end
  end

  context 'when the channel is secure' do
    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:secure_channel?).with(endpoint).and_return(true)
    end

    it 'adds the authorization header without resolving the endpoint address', :aggregate_failures do
      expect(params.dig('GkgServer', 'headers')).to include('authorization' => "Bearer #{jwt_token}")
      expect(Analytics::KnowledgeGraph::GrpcClient).not_to have_received(:private_address?)
    end
  end

  context 'when the channel is insecure and not private' do
    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:secure_channel?).with(endpoint).and_return(false)
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:private_address?).with(endpoint).and_return(false)
    end

    it 'does not include the authorization header' do
      expect(params.dig('GkgServer', 'headers')).not_to have_key('authorization')
    end
  end

  context 'when source_type is provided' do
    let(:source_type) { 'rest' }

    it 'passes source_type into JWT generation' do
      params

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: request_context)
    end
  end

  context 'when source_type is code_intelligence' do
    let(:source_type) { Analytics::KnowledgeGraph::SourceType::CODE_INTELLIGENCE }

    it 'passes it into JWT generation instead of falling back to rest' do
      params

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: having_attributes(source_type: source_type))
    end
  end

  context 'when source_type is invalid' do
    let(:source_type) { 'invalid' }

    it 'still generates a token, with rest' do
      allow(Gitlab::AppLogger).to receive(:warn)

      params

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: having_attributes(source_type: 'rest'))
    end
  end

  context 'when session_id is provided' do
    let(:request_context) do
      Analytics::KnowledgeGraph::RequestContext.new(source_type: source_type, session_id: 'workflow-abc-123')
    end

    it 'passes session_id into JWT generation' do
      params

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: request_context)
    end
  end

  context 'when request_id is provided' do
    let(:request_context) do
      Analytics::KnowledgeGraph::RequestContext.new(source_type: source_type, request_id: 'req-abc-123')
    end

    it 'passes request_id into JWT generation' do
      params

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: request_context)
    end
  end

  context 'when user_agent is provided' do
    let(:request_context) do
      Analytics::KnowledgeGraph::RequestContext.new(source_type: source_type, user_agent: 'TestAgent/1.0')
    end

    it 'includes x-client-user-agent in GkgServer headers' do
      expect(params.dig('GkgServer', 'headers')).to include('x-client-user-agent' => 'TestAgent/1.0')
    end
  end

  context 'when user_agent is nil' do
    it 'does not include x-client-user-agent in GkgServer headers' do
      expect(params.dig('GkgServer', 'headers')).not_to have_key('x-client-user-agent')
    end
  end
end
