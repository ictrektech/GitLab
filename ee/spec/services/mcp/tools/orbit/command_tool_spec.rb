# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Orbit::CommandTool, feature_category: :mcp_server do
  include_context 'with a stubbed Orbit query runner'

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, reporters: user) }

  let(:request) { Grape::Request.new(Rack::MockRequest.env_for('/api/v4/mcp?id=7')) }
  let(:context) { Mcp::Tools::RequestContext.new(current_user: user, request: request) }
  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:query_schema) do
    {
      'type' => 'object',
      'required' => ['query'],
      'properties' => { 'query' => { 'type' => 'string' }, 'format' => { 'type' => 'string', 'enum' => %w[llm raw] } },
      'additionalProperties' => false
    }
  end

  let(:command) { { name: 'query_graph', description: 'Query the graph.', parameters: query_schema } }
  let(:query) { 'MATCH (p:Project) RETURN p.id LIMIT 5' }

  subject(:tool) { described_class.new(command: command, context: context) }

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  before do
    stub_licensed_features(orbit: true)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
  end

  def execute(arguments)
    tool.execute(request: request, params: { name: command[:name], arguments: arguments })
  end

  it 'describes the command as a read-only tool in the orbit toolset', :aggregate_failures do
    expect(tool.to_h).to include(name: 'query_graph', description: 'Query the graph.', inputSchema: query_schema)
    expect(tool.toolset).to eq(:orbit)
    expect(tool.annotations).to eq(readOnlyHint: true)
    expect(tool.version).to eq('0.1.0')
  end

  describe '#execute' do
    context 'with query_graph' do
      it 'returns the Orbit query with the MCP request id and the query runner response', :aggregate_failures do
        result = execute({ 'query' => query })

        expect(result).to be_a(Analytics::Orbit::CommandInterceptor::OrbitQuery)
        expect(result.query_args).to include(query: query, user: user, format: :llm, mcp_id: '7',
          request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP))
        expect(result.response).to eq(orbit_runner_response)
        expect(result.response.error_reason).to be_nil
      end

      context 'when the query runner reports a failure' do
        let(:orbit_runner_response) do
          Analytics::KnowledgeGraph::QueryRunner::McpRenderer.new(7).query_error('compile_error', 'bad query', nil)
        end

        it 'keeps the response and exposes the failure reason', :aggregate_failures do
          result = execute({ 'query' => query })

          expect(result.response).to eq(orbit_runner_response)
          expect(result.response.error_reason).to eq(:bad_request)
        end
      end

      it 'keeps a query that looks like JSON as the text sent' do
        result = execute({ 'query' => '{"looks": "like json"}' })

        expect(result.query_args[:query]).to eq('{"looks": "like json"}')
      end

      it 'returns a validation error when the query is missing' do
        expect(execute({})).to include(
          content: [{ type: 'text', text: 'Validation error: query is missing' }], isError: true
        )
      end

      it 'returns an unauthorized tool error when the user has no Orbit-enabled group', :aggregate_failures do
        Analytics::KnowledgeGraph::EnabledNamespace.delete_all

        result = execute({ 'query' => query })

        expect(result).to include(
          content: [{ type: 'text', text: 'No Knowledge Graph enabled namespaces available' }], isError: true
        )
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end

      it 'returns a rate limit error when the user is throttled' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
          .with(request, user, :orbit_query, hash_including(scope: { user: user })).and_return(true)

        expect(execute({ 'query' => query }).dig(:structuredContent, :error, :type)).to eq('rate_limited')
      end

      it 'does not throttle a user in the Orbit rate limit allowlist', :clean_gitlab_redis_rate_limiting do
        stub_application_setting(orbit_query_limit: 1, orbit_rate_limit_allowlist: [user.username])

        results = Array.new(2) { execute({ 'query' => query }) }

        expect(results.last).to be_a(Analytics::Orbit::CommandInterceptor::OrbitQuery)
      end
    end

    context 'with another command' do
      let(:command) { { name: 'get_graph_schema', description: 'Get the schema.', parameters: { 'type' => 'object' } } }

      it 'returns the InvokeAgentCommand text', :aggregate_failures do
        allow(grpc_client).to receive(:invoke_agent_command).and_return({ formatted_text: 'schema text' })

        expect(execute({ 'format' => 'llm' })).to include(
          content: [{ type: 'text', text: 'schema text' }], isError: false
        )
        expect(grpc_client).to have_received(:invoke_agent_command).with(
          command_name: 'get_graph_schema', parameters: { 'format' => 'llm' }, user: user,
          request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP)
        )
      end

      it 'returns the result as JSON when it has no formatted text' do
        allow(grpc_client).to receive(:invoke_agent_command).and_return({ nodes: [] })

        expect(execute({})).to include(content: [{ type: 'text', text: '{"nodes":[]}' }], isError: false)
      end

      where(:grpc_code, :text, :reason) do
        [
          [GRPC::Core::StatusCodes::INVALID_ARGUMENT, 'bad parameters', :bad_request],
          [GRPC::Core::StatusCodes::FAILED_PRECONDITION, 'bad parameters', :bad_request],
          [GRPC::Core::StatusCodes::NOT_FOUND, 'bad parameters', :not_found],
          [GRPC::Core::StatusCodes::UNAUTHENTICATED, 'Orbit request failed', :error],
          [GRPC::Core::StatusCodes::UNAVAILABLE, 'Orbit request failed', :error],
          [GRPC::Core::StatusCodes::INTERNAL, 'Orbit request failed', :error]
        ]
      end

      with_them do
        it 'returns the Orbit error details only for a client error, with the matching reason', :aggregate_failures do
          allow(grpc_client).to receive(:invoke_agent_command).and_raise(
            Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'invoke_agent_command failed', grpc_code: grpc_code, grpc_details: 'bad parameters'
            )
          )

          result = execute({})

          expect(result).to include(content: [{ type: 'text', text: text }], isError: true)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(reason)
        end
      end

      it 'returns the generic error for a client error with no details' do
        allow(grpc_client).to receive(:invoke_agent_command).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'invoke_agent_command failed', grpc_code: GRPC::Core::StatusCodes::INVALID_ARGUMENT, grpc_details: ''
          )
        )

        expect(execute({})).to include(
          content: [{ type: 'text', text: 'Orbit request failed' }], isError: true
        )
      end
    end
  end
end
