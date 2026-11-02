# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::McpHandlers::CallTool, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp_orbit]) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:tool_name) { 'invoke_command' }
  let(:arguments) { invoke_command_arguments('query_graph', { 'query' => 'find pipelines' }) }
  let(:params) { { name: tool_name, arguments: arguments } }

  let(:request_context) do
    Analytics::KnowledgeGraph::RequestContext.new(source_type: Analytics::KnowledgeGraph::SourceType::MCP)
  end

  subject(:handler) do
    described_class.new(
      params,
      access_token,
      user,
      grpc_client: grpc_client,
      request_context: request_context
    )
  end

  def invoke_command_arguments(command_name, parameters)
    { 'command_name' => command_name, 'parameters' => parameters }
  end

  describe '#invoke' do
    before do
      auth_context = instance_double(
        Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true
      )
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
    end

    context 'when query_graph tool is called' do
      it 'returns an OrbitQuery with the query arguments' do
        result = handler.invoke

        expect(result).to be_a(described_class::OrbitQuery)
        expect(result.query_args).to include(query: 'find pipelines', user: user, format: :llm, mcp_id: nil)
      end
    end

    context 'when query_graph is called with format raw' do
      let(:arguments) { invoke_command_arguments('query_graph', { 'query' => 'find pipelines', 'format' => 'raw' }) }

      it 'passes raw format in the query arguments' do
        result = handler.invoke

        expect(result).to be_a(described_class::OrbitQuery)
        expect(result.query_args).to include(format: :raw)
      end
    end

    context 'when query_graph is called without format' do
      it 'defaults to llm format' do
        expect(handler.invoke.query_args).to include(format: :llm)
      end
    end

    context 'when query_graph is called with a Hash query' do
      let(:query) { { 'query_type' => 'search', 'node' => { 'id' => 'n', 'entity' => 'Project' } } }
      let(:arguments) { invoke_command_arguments('query_graph', { 'query' => query }) }

      it 'returns a tool error' do
        result = handler.invoke

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to eq("'query' must be GQL text")
      end
    end

    context 'when query_graph is called with an empty Hash query' do
      let(:arguments) { invoke_command_arguments('query_graph', { 'query' => {} }) }

      it 'returns a tool error' do
        result = handler.invoke

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to eq("'query' must be GQL text")
      end
    end

    context 'when query_graph is called without a query' do
      let(:arguments) { invoke_command_arguments('query_graph', {}) }

      it 'returns a tool error' do
        result = handler.invoke

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to eq("Missing required parameter 'query'")
      end
    end

    context 'when query_graph is called without enabled namespaces' do
      before do
        auth_context = instance_double(
          Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: false
        )
        allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
      end

      it 'returns a tool error response' do
        result = handler.invoke

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('No Knowledge Graph enabled namespaces available')
      end

      it 'does not return an OrbitQuery' do
        expect(handler.invoke).not_to be_a(described_class::OrbitQuery)
      end
    end

    context 'when list_commands is called' do
      let(:tool_name) { 'list_commands' }
      let(:arguments) { { 'command_names' => ['get_graph_schema'], 'format' => 'llm' } }
      let(:commands_result) do
        [{ name: 'get_graph_schema', description: 'Return the graph schema', parameters: { 'type' => 'object' } }]
      end

      before do
        allow(grpc_client).to receive(:list_agent_commands)
          .with(user: user, command_names: ['get_graph_schema'], format: :llm,
            request_context: an_instance_of(Analytics::KnowledgeGraph::RequestContext))
          .and_return({ formatted_text: "commands[1]:\n  - name: get_graph_schema" })
      end

      it 'returns the LLM-formatted command catalog from gRPC' do
        result = handler.invoke

        expect(result[:isError]).to be(false)
        expect(result[:content].first[:text]).to include('commands[1]:')
        expect(result[:content].first[:text]).to include('name: get_graph_schema')
      end

      context 'with raw format' do
        let(:arguments) { { 'command_names' => ['get_graph_schema'], 'format' => 'raw' } }

        before do
          allow(grpc_client).to receive(:list_agent_commands)
            .with(user: user, command_names: ['get_graph_schema'], format: :raw,
              request_context: an_instance_of(Analytics::KnowledgeGraph::RequestContext))
            .and_return(commands_result)
        end

        it 'returns command metadata from gRPC as JSON text' do
          result = handler.invoke

          expect(result[:isError]).to be(false)
          parsed = Gitlab::Json.safe_parse(result[:content].first[:text])
          expect(parsed.first['name']).to eq('get_graph_schema')
        end
      end
    end

    context 'when invoke_command falls through to GKG' do
      let(:tool_name) { 'invoke_command' }
      let(:arguments) do
        {
          'command_name' => 'get_graph_schema',
          'parameters' => { 'format' => 'llm' }
        }
      end

      before do
        allow(grpc_client).to receive(:invoke_agent_command)
          .with(command_name: 'get_graph_schema', parameters: { 'format' => 'llm' }, user: user,
            request_context: an_instance_of(Analytics::KnowledgeGraph::RequestContext))
          .and_return({ formatted_text: 'dsl text' })
      end

      it 'invokes the command through gRPC' do
        result = handler.invoke

        expect(result[:isError]).to be(false)
        expect(result[:content].first[:text]).to eq('dsl text')
      end
    end

    context 'when invoke_command intercepts query_graph' do
      let(:tool_name) { 'invoke_command' }
      let(:arguments) do
        {
          'command_name' => 'query_graph',
          'parameters' => { 'query' => 'find pipelines' }
        }
      end

      it 'routes to the Orbit query path' do
        result = handler.invoke

        expect(result).to be_a(described_class::OrbitQuery)
        expect(result.query_args).to include(query: 'find pipelines', user: user, format: :llm, mcp_id: nil)
      end
    end

    context 'when invoke_command receives downstream arguments at the top level' do
      let(:tool_name) { 'invoke_command' }
      let(:arguments) { { 'command_name' => 'get_graph_schema', 'format' => 'llm' } }

      it 'raises an invalid parameter error' do
        expect { handler.invoke }.to raise_error(ArgumentError, /Put downstream command inputs inside 'parameters'/)
      end
    end

    context 'when tool name is unknown' do
      let(:params) { { name: 'unknown_tool', arguments: {} } }

      it 'raises ArgumentError' do
        expect { handler.invoke }.to raise_error(ArgumentError, /Unknown tool: unknown_tool/)
      end
    end

    %w[query_graph get_graph_schema get_graph_status].each do |legacy_tool|
      context "when #{legacy_tool} (a removed legacy tool) is called" do
        let(:params) { { name: legacy_tool, arguments: {} } }

        it 'raises ArgumentError treating it as an unknown tool' do
          expect { handler.invoke }.to raise_error(ArgumentError, /Unknown tool: #{legacy_tool}/)
        end
      end
    end

    context 'when invoke_command raises ConnectionError' do
      let(:arguments) { invoke_command_arguments('get_graph_schema', {}) }

      before do
        allow(grpc_client).to receive(:invoke_agent_command)
          .and_raise(Analytics::KnowledgeGraph::GrpcClient::ConnectionError, 'connection refused')
      end

      it 'raises API::Orbit::Mcp::InternalError' do
        expect { handler.invoke }.to raise_error(API::Orbit::Mcp::InternalError, /connection refused/)
      end
    end

    context 'when invoke_command raises a client-class ConnectionError' do
      let(:arguments) { invoke_command_arguments('no_such_command', {}) }

      where(:grpc_code) do
        [
          GRPC::Core::StatusCodes::INVALID_ARGUMENT,
          GRPC::Core::StatusCodes::NOT_FOUND,
          GRPC::Core::StatusCodes::FAILED_PRECONDITION
        ]
      end

      with_them do
        before do
          allow(grpc_client).to receive(:invoke_agent_command).and_raise(
            Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'invoke_agent_command failed', grpc_code: grpc_code, grpc_details: 'Tool not found: no_such_command'
            )
          )
        end

        it 'returns MCP error result with the gRPC details' do
          result = handler.invoke

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to eq('Tool not found: no_such_command')
        end
      end
    end

    context 'when invoke_command raises a client-class ConnectionError without details' do
      let(:arguments) { invoke_command_arguments('no_such_command', {}) }

      before do
        allow(grpc_client).to receive(:invoke_agent_command).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'invoke_agent_command failed', grpc_code: GRPC::Core::StatusCodes::NOT_FOUND, grpc_details: ''
          )
        )
      end

      it 'raises API::Orbit::Mcp::InternalError' do
        expect { handler.invoke }.to raise_error(API::Orbit::Mcp::InternalError, /invoke_agent_command failed/)
      end
    end

    context 'when invoke_command raises a ConnectionError whose details must stay internal' do
      let(:arguments) { invoke_command_arguments('get_graph_schema', {}) }

      where(:grpc_code) do
        [
          GRPC::Core::StatusCodes::UNAVAILABLE,
          GRPC::Core::StatusCodes::INTERNAL,
          GRPC::Core::StatusCodes::UNAUTHENTICATED
        ]
      end

      with_them do
        before do
          allow(grpc_client).to receive(:invoke_agent_command).and_raise(
            Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
              'invoke_agent_command failed', grpc_code: grpc_code, grpc_details: 'internal detail'
            )
          )
        end

        it 'raises API::Orbit::Mcp::InternalError' do
          expect { handler.invoke }.to raise_error(API::Orbit::Mcp::InternalError, /invoke_agent_command failed/)
        end
      end
    end

    context 'when tool name is missing' do
      let(:params) { { name: nil, arguments: {} } }

      it 'raises ArgumentError' do
        expect { handler.invoke }.to raise_error(ArgumentError)
      end
    end

    context 'when tool name is empty' do
      let(:params) { { name: '', arguments: {} } }

      it 'raises ArgumentError' do
        expect { handler.invoke }.to raise_error(ArgumentError)
      end
    end

    context 'when session_id is provided' do
      subject(:handler) do
        described_class.new(
          params,
          access_token,
          user,
          grpc_client: grpc_client,
          request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP,
            session_id: 'workflow-abc-123'
          )
        )
      end

      context 'when calling query_graph' do
        it 'passes session_id in the query arguments' do
          expect(handler.invoke.query_args[:request_context]).to have_attributes(session_id: 'workflow-abc-123')
        end
      end
    end

    context 'when session_id is not provided' do
      it 'passes nil session_id in the query arguments' do
        expect(handler.invoke.query_args[:request_context]).to have_attributes(session_id: nil)
      end
    end

    context 'when user_agent is provided' do
      subject(:handler) do
        described_class.new(
          params,
          access_token,
          user,
          grpc_client: grpc_client,
          request_context: Analytics::KnowledgeGraph::RequestContext.new(
            source_type: Analytics::KnowledgeGraph::SourceType::MCP,
            user_agent: 'TestAgent/1.0'
          )
        )
      end

      context 'when calling query_graph' do
        it 'passes user_agent in the query arguments' do
          expect(handler.invoke.query_args[:request_context]).to have_attributes(user_agent: 'TestAgent/1.0')
        end
      end

      context 'when calling list_commands' do
        let(:tool_name) { 'list_commands' }
        let(:arguments) { { 'command_names' => ['get_graph_schema'], 'format' => 'llm' } }

        before do
          allow(grpc_client).to receive(:list_agent_commands)
            .and_return({ formatted_text: "commands[1]:\n  - name: get_graph_schema" })
        end

        it 'passes user_agent to grpc_client.list_agent_commands' do
          handler.invoke

          expect(grpc_client).to have_received(:list_agent_commands)
            .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
        end
      end

      context 'when calling invoke_command' do
        let(:tool_name) { 'invoke_command' }
        let(:arguments) { { 'command_name' => 'get_graph_schema', 'parameters' => { 'format' => 'llm' } } }

        before do
          allow(grpc_client).to receive(:invoke_agent_command).and_return({ formatted_text: 'dsl text' })
        end

        it 'passes user_agent to grpc_client.invoke_agent_command' do
          handler.invoke

          expect(grpc_client).to have_received(:invoke_agent_command)
            .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
        end
      end
    end

    context 'when user_agent is not provided' do
      it 'passes nil user_agent in the query arguments' do
        expect(handler.invoke.query_args[:request_context]).to have_attributes(user_agent: nil)
      end
    end
  end
end
