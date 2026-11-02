# frozen_string_literal: true

require "spec_helper"

RSpec.describe API::Orbit::Mcp, feature_category: :knowledge_graph do
  include_context 'with a stubbed Orbit query runner'

  let_it_be_with_reload(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp_orbit]) }
  let_it_be(:group) { create(:group) }

  let(:initialize_params) do
    { jsonrpc: '2.0', method: 'initialize', id: '1', params: { protocolVersion: '2025-06-18' } }
  end

  before_all do
    group.add_reporter(user)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  describe 'POST /orbit/mcp' do
    context 'when unauthenticated' do
      it 'returns a WWW-Authenticate challenge pointing at the resource metadata', :aggregate_failures do
        post api('/orbit/mcp')

        metadata_url = "#{Gitlab.config.gitlab.url}/.well-known/oauth-protected-resource/api/v4/orbit/mcp"
        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.headers['WWW-Authenticate'])
          .to eq(%(Bearer realm="GitLab", scope="mcp_orbit", resource_metadata="#{metadata_url}"))
      end
    end

    context 'when user belongs to a group with Premium plan' do
      it 'returns success for initialize' do
        post api('/orbit/mcp', user, oauth_access_token: access_token), params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq({
          "id" => "1",
          "jsonrpc" => "2.0",
          "result" => {
            "capabilities" => { "tools" => { "listChanged" => false } },
            "protocolVersion" => "2025-06-18",
            "serverInfo" => { "name" => "GitLab Orbit MCP Server", "version" => Gitlab::VERSION }
          }
        })
      end
    end

    # Session IDs were optional for servers in the 2025 revisions and removed in 2026-07-28,
    # which tells a server to ignore the header rather than mint or echo an ID of its own.
    context 'for every supported protocol version' do
      API::Orbit::McpHandlers::InitializeRequest::SUPPORTED_PROTOCOL_VERSIONS.each do |version|
        context "with #{version}" do
          let(:versioned_params) { initialize_params.merge(params: { protocolVersion: version }) }

          it 'negotiates a supported version and echoes the request id', :aggregate_failures do
            post api('/orbit/mcp', user, oauth_access_token: access_token), params: versioned_params

            expect(response).to have_gitlab_http_status(:ok)
            expect(API::Orbit::McpHandlers::InitializeRequest::SUPPORTED_PROTOCOL_VERSIONS)
              .to include(json_response['result']['protocolVersion'])
            expect(json_response['id']).to eq('1')
          end

          it 'ignores an Mcp-Session-Id header and assigns no session', :aggregate_failures do
            post api('/orbit/mcp', user, oauth_access_token: access_token), params: versioned_params,
              headers: { 'Mcp-Session-Id' => 'client-supplied-session' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(API::Orbit::McpHandlers::InitializeRequest::SUPPORTED_PROTOCOL_VERSIONS)
              .to include(json_response['result']['protocolVersion'])
            expect(json_response['id']).to eq('1')
            expect(response.headers['Mcp-Session-Id']).to be_nil
          end
        end
      end
    end

    context 'when orbit licensed feature is not available' do
      before do
        stub_licensed_features(orbit: false)
      end

      it 'returns forbidden' do
        post api('/orbit/mcp', user, oauth_access_token: access_token), params: initialize_params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'with OAuth token scopes' do
      using RSpec::Parameterized::TableSyntax

      where(:scope_description, :token_scopes, :expected_status) do
        'mcp_orbit'         | [:mcp_orbit]       | :ok
        'mcp'               | [:mcp]             | :ok
        'read_api'          | [:read_api]        | :ok
        'api'               | [:api]             | :ok
        'ai_workflows'      | [:ai_workflows]    | :ok
        'api and mcp_orbit' | [:api, :mcp_orbit] | :ok
        'read_user'         | [:read_user]       | :forbidden
      end

      with_them do
        let(:scoped_token) { create(:oauth_access_token, user: user, scopes: token_scopes) }

        it 'enforces the accepted scopes', :aggregate_failures do
          post api('/orbit/mcp', user, oauth_access_token: scoped_token), params: initialize_params

          expect(response).to have_gitlab_http_status(expected_status)
          expect(json_response['error']).to eq('insufficient_scope') if expected_status == :forbidden
        end
      end
    end

    context 'with a personal access token' do
      let_it_be(:read_api_pat) { create(:personal_access_token, user: user, scopes: [:read_api]) }
      let_it_be(:api_pat) { create(:personal_access_token, user: user, scopes: [:api]) }
      let_it_be(:read_user_pat) { create(:personal_access_token, user: user, scopes: [:read_user]) }

      it 'accepts a read_api token sent in the PRIVATE-TOKEN header' do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => read_api_pat.token }, params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'accepts a read_api token sent in the Authorization header' do
        post api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{read_api_pat.token}" },
          params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'accepts a read_api token sent in the access_token query parameter' do
        post api('/orbit/mcp', access_token: read_api_pat), params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'accepts an api token, which is a superset of read_api' do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => api_pat.token }, params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'rejects a read_user token' do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => read_user_pat.token }, params: initialize_params

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'with a group access token' do
      let_it_be(:group_access_token) do
        create(:resource_access_token, resource: group, access_level: Gitlab::Access::REPORTER,
          scopes: [:read_api])
      end

      it 'accepts a read_api token sent in the PRIVATE-TOKEN header' do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => group_access_token.token },
          params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'accepts a read_api token sent in the Authorization header' do
        post api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{group_access_token.token}" },
          params: initialize_params

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the token scope is rejected' do
      let_it_be(:read_user_pat) { create(:personal_access_token, user: create(:user), scopes: [:read_user]) }

      it 'returns insufficient_scope for a rejected scope', :aggregate_failures do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => read_user_pat.token }, params: initialize_params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['error']).to eq('insufficient_scope')
      end

      it 'answers with the challenge of the 401, naming every scope it accepts, mcp_orbit first', :aggregate_failures do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => read_user_pat.token }, params: initialize_params

        metadata_url = "#{Gitlab.config.gitlab.url}/.well-known/oauth-protected-resource/api/v4/orbit/mcp"
        expect(json_response['scope']).to eq('mcp_orbit mcp read_api ai_workflows api')
        expect(response.headers['WWW-Authenticate']).to eq(
          %(Bearer realm="GitLab", error="insufficient_scope", ) +
            %(error_description="The request requires higher privileges than provided by the access token.", ) +
            %(scope="mcp_orbit mcp read_api ai_workflows api", resource_metadata="#{metadata_url}")
        )
      end
    end

    context 'when the token is revoked' do
      let_it_be(:revoked_pat) { create(:personal_access_token, :revoked, user: user, scopes: [:read_api]) }

      it 'answers with the challenge of the 401, adding the error', :aggregate_failures do
        post api('/orbit/mcp'), headers: { 'PRIVATE-TOKEN' => revoked_pat.token }, params: initialize_params

        metadata_url = "#{Gitlab.config.gitlab.url}/.well-known/oauth-protected-resource/api/v4/orbit/mcp"
        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.headers['WWW-Authenticate']).to eq(
          %(Bearer realm="GitLab", error="invalid_token", ) +
            %(error_description="Token was revoked. You have to re-authorize from the user.", ) +
            %(scope="mcp_orbit", resource_metadata="#{metadata_url}")
        )
      end
    end

    context 'when authenticated with a session and no access token' do
      before do
        login_as(user)
      end

      it 'returns unauthorized with a WWW-Authenticate challenge', :aggregate_failures do
        post api('/orbit/mcp'), params: initialize_params

        metadata_url = "#{Gitlab.config.gitlab.url}/.well-known/oauth-protected-resource/api/v4/orbit/mcp"
        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.headers['WWW-Authenticate'])
          .to eq(%(Bearer realm="GitLab", scope="mcp_orbit", resource_metadata="#{metadata_url}"))
      end
    end

    context 'when required jsonrpc param is missing' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token), params: { id: '1', method: 'initialize' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('jsonrpc is missing')
      end
    end

    context 'when required jsonrpc param is empty' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '', method: 'initialize', id: '1' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('jsonrpc is empty')
      end
    end

    context 'when required jsonrpc param is invalid value' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '1.0', method: 'initialize', id: '1' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('jsonrpc does not have a valid value')
      end

      it 'echoes a string request id' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '1.0', method: 'initialize', id: 'abc-123' }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(json_response['id']).to eq('abc-123')
      end

      it 'echoes an integer request id without changing its type', :aggregate_failures do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '1.0', method: 'initialize', id: 7 }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(json_response['id']).to eq(7)
        expect(json_response['id']).to be_a(Integer)
      end

      it 'returns a null id when the request id is neither an integer nor a string' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '1.0', method: 'initialize', id: { foo: 'bar' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(json_response['id']).to be_nil
      end
    end

    context 'when params are invalid' do
      it 'returns JSON-RPC Invalid params error that echoes the request id' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'initialize', id: 'abc-123',
                    params: { protocolVersion: '1999-01-01' } }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32602)
        expect(json_response['id']).to eq('abc-123')
      end
    end

    context 'when required method param is missing' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token), params: { jsonrpc: '2.0', id: '1' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('method is missing')
      end
    end

    context 'when required method param is empty' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: '', id: '1' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('method is empty')
      end
    end

    context 'when id param is an integer' do
      it 'preserves the integer type in the response', :aggregate_failures do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'initialize', id: 1,
                    params: { protocolVersion: '2025-06-18' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq(1)
        expect(json_response['id']).to be_a(Integer)
      end
    end

    context 'when id param is a string' do
      it 'preserves the string type in the response', :aggregate_failures do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'initialize', id: 'abc-123',
                    params: { protocolVersion: '2025-06-18' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq('abc-123')
        expect(json_response['id']).to be_a(String)
      end
    end

    context 'when optional id param is empty' do
      it 'returns JSON-RPC Invalid Request error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'initialize', id: '' }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32600)
        expect(json_response['error']['data']['validations']).to include('id is empty')
      end
    end

    context 'when method does not exist' do
      it 'returns JSON-RPC Method not found error' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'unknown/method', id: '1' }

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['error']['code']).to eq(-32601)
        expect(json_response['error']['message']).to eq('Method not found')
      end
    end

    context 'when method is ping' do
      it 'returns success with an empty result', :aggregate_failures do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'ping', id: 1 }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq({
          'jsonrpc' => '2.0',
          'id' => 1,
          'result' => {}
        })
      end
    end

    context 'when notifications/initialized is sent without id' do
      it 'returns accepted with an empty body', :aggregate_failures do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'notifications/initialized' }

        expect(response).to have_gitlab_http_status(:accepted)
        expect(response.body).to be_empty
      end
    end

    context 'when a notification without a handler is sent' do
      it 'returns accepted with an empty body and does not build a gRPC client', :aggregate_failures do
        expect(::Analytics::KnowledgeGraph::GrpcClient).not_to receive(:new)

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'notifications/cancelled',
                    params: { requestId: 1, reason: 'test' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_gitlab_http_status(:accepted)
        expect(response.body).to be_empty
      end
    end

    describe 'tools/list' do
      let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
      let(:grpc_tools) do
        [
          {
            name: 'query_graph',
            description: 'Query the knowledge graph',
            parameters: { 'type' => 'object', 'properties' => { 'query' => { 'type' => 'string' } } }
          },
          {
            name: 'get_graph_schema',
            description: 'Get the graph schema',
            parameters: { 'type' => 'object' }
          },
          {
            name: 'list_commands',
            description: 'List Orbit commands',
            parameters: { 'type' => 'object' }
          },
          {
            name: 'invoke_command',
            description: 'Invoke an Orbit command',
            parameters: { 'type' => 'object' }
          }
        ]
      end

      before do
        allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
      end

      it 'returns only the command wrapper tools from gRPC' do
        allow(grpc_client).to receive(:list_tools)
          .with(user: user,
            request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP))
          .and_return(grpc_tools)

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/list', id: '1' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['result']['tools'].pluck('name')).to eq(%w[list_commands invoke_command])
        expect(json_response['result']['tools'].first['inputSchema']).to be_present
      end

      it 'uses dws source_type when ai_workflows scope is present' do
        dws_access_token = create(:oauth_access_token, user: user, scopes: [:mcp_orbit, :ai_workflows])

        allow(grpc_client).to receive(:list_tools)
          .with(user: user,
            request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::DWS))
          .and_return(grpc_tools)

        post api('/orbit/mcp', user, oauth_access_token: dws_access_token),
          params: { jsonrpc: '2.0', method: 'tools/list', id: '1' }

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when access_token is nil (session-authenticated user)' do
        before do
          allow(::Analytics::KnowledgeGraph::SourceType).to receive(:for_mcp_request)
            .and_return(Analytics::KnowledgeGraph::SourceType::MCP)
          allow(grpc_client).to receive(:list_tools)
            .with(user: user,
              request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP))
            .and_return(grpc_tools)
        end

        it 'delegates to SourceType.for_mcp_request' do
          post api('/orbit/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/list', id: '1' }

          expect(::Analytics::KnowledgeGraph::SourceType).to have_received(:for_mcp_request)
          expect(grpc_client).to have_received(:list_tools)
            .with(user: user,
              request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP))
        end
      end
    end

    describe 'tools/call' do
      let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }

      before do
        allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)

        auth_context = instance_double(
          Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true
        )
        allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
      end

      it 'runs the query when invoke_command dispatches query_graph' do
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .and_return({})

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'query_graph',
                                           parameters: { query: 'pipelines' } } } }

        expect(response).to have_gitlab_http_status(:ok)
        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new).with(anything, user: user, env: anything)
      end

      context 'with a query runner response' do
        let(:envelope) do
          { jsonrpc: '2.0', result: { content: [{ type: 'text', text: 'rows' }], isError: false }, id: '1' }
        end

        let(:orbit_runner_response) do
          Analytics::KnowledgeGraph::QueryRunner::Response.new(
            status: 200, content_type: 'application/json', body: "#{envelope.to_json}\n"
          )
        end

        before do
          allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token).and_return('test-jwt-token')
        end

        it 'renders the query runner response', :aggregate_failures do
          post api('/orbit/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                      params: { name: 'invoke_command',
                                arguments: { command_name: 'query_graph',
                                             parameters: { query: 'pipelines' } } } }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.media_type).to eq('application/json')
          expect(response.body).to eq("#{envelope.to_json}\n")
          expect(response.headers[::Gitlab::Workhorse::SEND_DATA_HEADER]).to be_nil
          expect(response.headers['ETag']).not_to eq(%(W/"#{Digest::SHA256.hexdigest(response.body)[0, 32]}"))
        end
      end

      it 'returns a tool error for a JSON object query' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: Gitlab::Json.dump(
            jsonrpc: '2.0', method: 'tools/call', id: '1',
            params: { name: 'invoke_command',
                      arguments: { command_name: 'query_graph', parameters: { query: { nodes: ['User'] } } } }
          ), headers: { 'CONTENT_TYPE' => 'application/json' }

        expect(json_response.dig('result', 'isError')).to be(true)
      end

      context 'with a GQL query' do
        using RSpec::Parameterized::TableSyntax

        let(:query) { " MATCH (u:User {name: 'Zoë \\\"雪\\\"'}) RETURN u LIMIT 1\n" }

        where(:format) { %w[raw gql] }

        with_them do
          it 'forwards the query text, format, and context', :aggregate_failures do
            allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
              .and_return({})

            post api('/orbit/mcp', user, oauth_access_token: access_token),
              params: Gitlab::Json.dump(
                jsonrpc: '2.0', method: 'tools/call', id: 'gql-request',
                params: {
                  name: 'invoke_command',
                  arguments: {
                    command_name: 'query_graph', parameters: { query: query, format: format }
                  }
                }
              ), headers: { 'CONTENT_TYPE' => 'application/json', 'User-Agent' => 'TestAgent/1.0',
                            'X-Duo-Workflow-Session-Id' => 'workflow-gql' }

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for).with(
              query: query, user: user, format: format.to_sym, mcp_id: 'gql-request',
              request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP,
                session_id: 'workflow-gql', user_agent: 'TestAgent/1.0')
            )
          end
        end
      end

      it 'passes dws source_type to the query runner when ai_workflows scope is present' do
        dws_access_token = create(:oauth_access_token, user: user, scopes: [:mcp_orbit, :ai_workflows])

        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .with(hash_including(
            request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::DWS)))
          .and_return({})

        post api('/orbit/mcp', user, oauth_access_token: dws_access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'query_graph',
                                           parameters: { query: 'pipelines' } } } }

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'returns result from gRPC on success for invoke_command' do
        allow(grpc_client).to receive(:invoke_agent_command)
          .with(hash_including(command_name: 'get_graph_schema', user: user))
          .and_return({ formatted_text: 'dsl text' })

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'get_graph_schema', parameters: {} } } }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['result']['isError']).to be(false)
      end

      it 'passes X-Duo-Workflow-Session-Id to the query runner when invoke_command dispatches query_graph' do
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .with(hash_including(request_context: having_attributes(session_id: 'workflow-xyz-789')))
          .and_return({})

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'query_graph',
                                           parameters: { query: 'pipelines' } } } },
          headers: { 'X-Duo-Workflow-Session-Id' => 'workflow-xyz-789' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for)
          .with(hash_including(request_context: having_attributes(session_id: 'workflow-xyz-789')))
      end

      it 'extracts X-Duo-Workflow-Session-Id header and passes to gRPC for list_commands' do
        allow(grpc_client).to receive(:list_agent_commands)
          .with(hash_including(request_context: having_attributes(session_id: 'workflow-xyz-789')))
          .and_return({ formatted_text: 'commands' })

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'list_commands', arguments: {} } },
          headers: { 'X-Duo-Workflow-Session-Id' => 'workflow-xyz-789' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(grpc_client).to have_received(:list_agent_commands)
          .with(hash_including(request_context: having_attributes(session_id: 'workflow-xyz-789')))
      end

      it 'passes nil session_id when X-Duo-Workflow-Session-Id header is absent' do
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .and_return({})

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'query_graph',
                                           parameters: { query: 'pipelines' } } } }

        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for)
          .with(hash_including(request_context: having_attributes(session_id: nil)))
      end

      it 'forwards User-Agent to the query runner when invoke_command dispatches query_graph' do
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
          .and_return({})

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'invoke_command',
                              arguments: { command_name: 'query_graph',
                                           parameters: { query: 'pipelines' } } } },
          headers: { 'User-Agent' => 'TestAgent/1.0' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for)
          .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
      end

      it 'forwards User-Agent to gRPC for list_commands' do
        allow(grpc_client).to receive(:list_agent_commands)
          .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
          .and_return({ formatted_text: 'commands' })

        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'list_commands', arguments: {} } },
          headers: { 'User-Agent' => 'TestAgent/1.0' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(grpc_client).to have_received(:list_agent_commands)
          .with(hash_including(request_context: having_attributes(user_agent: 'TestAgent/1.0')))
      end

      it 'rejects removed legacy tools' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'query_graph', arguments: { query: 'pipelines' } } }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32602)
      end

      it 'rejects unknown tools' do
        post api('/orbit/mcp', user, oauth_access_token: access_token),
          params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                    params: { name: 'unknown_tool', arguments: {} } }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']['code']).to eq(-32602)
      end

      context 'when a governing namespace must be selected' do
        let_it_be(:candidate_a) { create(:group, name: 'mcp-candidate-a') }
        let_it_be(:candidate_b) { create(:group, name: 'mcp-candidate-b') }

        let(:governing_namespace_candidates) { [candidate_a, candidate_b] }
        let(:single_candidate_fallback) { nil }
        let(:governing_namespace_finder) do
          instance_double(
            Analytics::KnowledgeGraph::GoverningNamespaceFinder,
            candidates: governing_namespace_candidates,
            single_candidate_fallback: single_candidate_fallback
          )
        end

        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          allow(Analytics::KnowledgeGraph::OrbitLicense).to receive(:available_for?).and_return(true)
          allow(Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for)
            .and_return(governing_namespace_finder)
          allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token).and_return('test-jwt-token')
        end

        def call_query_graph
          post api('/orbit/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                      params: { name: 'invoke_command',
                                arguments: { command_name: 'query_graph',
                                             parameters: { query: 'pipelines' } } } }
        end

        it 'returns a JSON-RPC error carrying the contract', :aggregate_failures do
          call_query_graph

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response).to eq(
            'jsonrpc' => '2.0',
            'id' => '1',
            'error' => {
              'code' => -32600,
              'message' => 'Invalid Request',
              'data' => {
                'code' => 'billing_namespace_required',
                'message' => s_('Orbit|Select a default group in your preferences to run GitLab Orbit queries.'),
                'deep_link' => Gitlab::Routing.url_helpers.profile_preferences_url,
                'candidates' => [
                  { 'id' => candidate_a.id, 'name' => 'mcp-candidate-a' },
                  { 'id' => candidate_b.id, 'name' => 'mcp-candidate-b' }
                ]
              }
            }
          )
        end

        context 'when no candidates exist' do
          let(:governing_namespace_candidates) { [] }

          it 'returns a JSON-RPC error with an empty candidates list', :aggregate_failures do
            call_query_graph

            expect(response).to have_gitlab_http_status(:unprocessable_entity)
            expect(json_response.dig('error', 'data')).to include('code' => 'billing_namespace_required',
              'candidates' => [])
          end
        end

        context 'when exactly one candidate exists' do
          let(:governing_namespace_candidates) { [candidate_a] }
          let(:single_candidate_fallback) { candidate_a }

          it 'dispatches the query', :aggregate_failures do
            call_query_graph

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new)
          end
        end

        context 'when the preference is set' do
          before do
            allow(governing_namespace_finder).to receive(:eligible?).with(candidate_a.id).and_return(true)
            user.user_preference.update!(knowledge_graph_governing_namespace_id: candidate_a.id)
          end

          it 'dispatches the query', :aggregate_failures do
            call_query_graph

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new)
          end
        end

        context 'when knowledge_graph_billing is disabled' do
          before do
            stub_feature_flags(knowledge_graph_billing: false)
          end

          it 'dispatches the query', :aggregate_failures do
            call_query_graph

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new)
          end
        end

        it 'does not block introspection tools' do
          allow(grpc_client).to receive(:list_agent_commands).and_return({ formatted_text: 'commands' })

          post api('/orbit/mcp', user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                      params: { name: 'list_commands', arguments: {} } }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    describe 'rate limiting', :clean_gitlab_redis_rate_limiting do
      let(:current_user) { user }

      let(:query_graph_params) do
        { jsonrpc: '2.0', method: 'tools/call', id: '1',
          params: { name: 'invoke_command',
                    arguments: { command_name: 'query_graph', parameters: { query: 'pipelines' } } } }
      end

      before do
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .and_return({})

        auth_context = instance_double(
          Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true
        )
        allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
      end

      it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
        def request
          post api('/orbit/mcp', current_user, oauth_access_token: access_token), params: query_graph_params
        end
      end

      context 'when the tools/call does not dispatch query_graph' do
        it 'does not apply the orbit_query rate limit to list_commands' do
          allow_next_instance_of(Analytics::KnowledgeGraph::GrpcClient) do |client|
            allow(client).to receive(:list_agent_commands).and_return({ formatted_text: 'commands' })
          end
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:orbit_query, any_args)

          post api('/orbit/mcp', current_user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                      params: { name: 'list_commands', arguments: {} } }

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'does not apply the orbit_query rate limit to invoke_command with another command' do
          allow_next_instance_of(Analytics::KnowledgeGraph::GrpcClient) do |client|
            allow(client).to receive(:invoke_agent_command).and_return({ formatted_text: 'dsl text' })
          end
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:orbit_query, any_args)

          post api('/orbit/mcp', current_user, oauth_access_token: access_token),
            params: { jsonrpc: '2.0', method: 'tools/call', id: '1',
                      params: { name: 'invoke_command',
                                arguments: { command_name: 'get_graph_schema', parameters: {} } } }

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the method is not tools/call' do
        it 'does not apply the orbit_query rate limit to initialize' do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?).with(:orbit_query, any_args)

          post api('/orbit/mcp', current_user, oauth_access_token: access_token), params: initialize_params

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'with granular token authorization' do
      context 'when the token is granular' do
        let(:granular_permission) do
          ::Authz::PermissionGroups::Assignable.for_permission(:read_orbit).first.name
        end

        let(:granular_pat) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
            permissions: [granular_permission])
        end

        it 'clears scope enforcement without carrying an accepted scope', :aggregate_failures do
          expect(granular_pat.scopes).to eq(['granular'])

          post api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{granular_pat.token}" },
            params: initialize_params

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the token holds the deprecated execute_orbit_mcp_tool permission' do
        let(:old_pat) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
            permissions: ['execute_orbit_mcp_tool'])
        end

        it 'denies Orbit MCP access' do
          post api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{old_pat.token}" },
            params: initialize_params

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      it_behaves_like 'authorizing granular token permissions', :read_orbit,
        legacy_token_scopes: [:mcp_orbit] do
        let(:boundary_object) { :user }
        let(:request) do
          post api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{pat.token}" }, params: initialize_params
        end
      end
    end
  end

  describe 'GET /orbit/mcp' do
    context 'when unauthenticated' do
      it 'returns authentication error' do
        get api('/orbit/mcp')

        expect(response).to have_gitlab_http_status(:unauthorized)
      end

      it 'returns a WWW-Authenticate challenge pointing at the resource metadata', :aggregate_failures do
        get api('/orbit/mcp')

        metadata_url = "#{Gitlab.config.gitlab.url}/.well-known/oauth-protected-resource/api/v4/orbit/mcp"
        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(response.headers['WWW-Authenticate'])
          .to eq(%(Bearer realm="GitLab", scope="mcp_orbit", resource_metadata="#{metadata_url}"))
      end
    end

    context 'when authenticated' do
      it 'returns method not allowed' do
        get api('/orbit/mcp', user, oauth_access_token: access_token)

        expect(response).to have_gitlab_http_status(:method_not_allowed)
      end

      context 'when access token has read_api scope' do
        let(:read_api_access_token) { create(:oauth_access_token, user: user, scopes: [:read_api]) }

        it 'returns method not allowed' do
          get api('/orbit/mcp', user, oauth_access_token: read_api_access_token)

          expect(response).to have_gitlab_http_status(:method_not_allowed)
        end
      end
    end

    context 'with granular token authorization' do
      it_behaves_like 'authorizing granular token permissions', :read_orbit,
        expected_success_status: :method_not_allowed, legacy_token_scopes: [:mcp_orbit] do
        let(:boundary_object) { :user }
        let(:request) { get api('/orbit/mcp'), headers: { 'Authorization' => "Bearer #{pat.token}" } }
      end
    end
  end
end
