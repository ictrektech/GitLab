# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/SpecFilePathFormat -- JSON-RPC has single path for method invocation
RSpec.describe API::Mcp, 'Orbit tools', :use_clean_rails_memory_store_caching,
  feature_category: :mcp_server do
  include_context 'with a stubbed Orbit query runner'

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, reporters: user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }

  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:orbit_toolset_header) { { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => 'orbit' } }
  let(:request_options) { {} }
  let(:commands) do
    [
      { name: 'query_graph', description: 'Query the graph.',
        parameters: {
          'type' => 'object',
          'required' => ['query'],
          'properties' => {
            'query' => { 'type' => 'string', 'description' => 'GQL query text.' },
            'format' => { 'type' => 'string', 'enum' => %w[llm raw] }
          },
          'additionalProperties' => false
        } },
      { name: 'get_graph_schema', description: 'Get the graph schema.',
        parameters: { 'type' => 'object', 'properties' => {} } }
    ]
  end

  before do
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_feature_flags(orbit_promo_access_gate: false)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:list_agent_commands).and_return(commands)
  end

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  def post_mcp(method, params: nil, headers: orbit_toolset_header, id: '1', auth: { oauth_access_token: access_token })
    post api('/mcp', user, **auth),
      params: { jsonrpc: '2.0', method: method, id: id, params: params }.compact, headers: headers, as: :json
  end

  def listed_orbit_tools
    json_response.dig('result', 'tools').select { |tool| tool.dig('_meta', 'com.gitlab/toolset') == 'orbit' }
  end

  describe 'tools/list' do
    it 'lists each Orbit command as a read-only tool in the orbit toolset', :aggregate_failures do
      post_mcp('tools/list')

      expect(response).to have_gitlab_http_status(:ok)
      expect(listed_orbit_tools).to contain_exactly(
        hash_including('name' => 'query_graph', 'description' => 'Query the graph.',
          'inputSchema' => commands.first[:parameters],
          'annotations' => { 'readOnlyHint' => true },
          '_meta' => { 'com.gitlab/toolset' => 'orbit' }),
        hash_including('name' => 'get_graph_schema')
      )
    end

    it 'includes the Orbit tools for the all toolset' do
      post_mcp('tools/list', headers: { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => 'all' })

      expect(listed_orbit_tools.pluck('name')).to contain_exactly('query_graph', 'get_graph_schema')
    end

    it 'caches the Orbit commands across requests' do
      2.times { post_mcp('tools/list') }

      expect(grpc_client).to have_received(:list_agent_commands).once
    end

    context 'when the orbit toolset is not selected' do
      it 'does not list or fetch the Orbit tools', :aggregate_failures do
        post_mcp('tools/list', headers: {})

        expect(listed_orbit_tools).to be_empty
        expect(grpc_client).not_to have_received(:list_agent_commands)
      end
    end

    context 'when only tool names are selected' do
      it 'does not list the Orbit tools' do
        post_mcp('tools/list', headers: { 'X-Gitlab-Enabled-Mcp-Server-Tools' => 'query_graph' })

        expect(listed_orbit_tools).to be_empty
      end
    end

    shared_examples 'Orbit tools are not listed' do
      it 'does not list or fetch the Orbit tools', :aggregate_failures do
        post_mcp('tools/list', **request_options)

        expect(response).to have_gitlab_http_status(:ok)
        expect(listed_orbit_tools).to be_empty
        expect(grpc_client).not_to have_received(:list_agent_commands)
      end
    end

    context 'when the Orbit service is not configured on the instance' do
      before do
        stub_config(knowledge_graph: { 'enabled' => false })
      end

      it_behaves_like 'Orbit tools are not listed'
    end

    context 'when the instance license does not include Orbit' do
      before do
        stub_licensed_features(orbit: false)
      end

      it_behaves_like 'Orbit tools are not listed'
    end

    context 'when the user has no Orbit-enabled group' do
      before do
        Analytics::KnowledgeGraph::EnabledNamespace.delete_all
      end

      it_behaves_like 'Orbit tools are not listed'
    end

    context 'with a granular personal access token' do
      def granular_pat(*permissions)
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
          permissions: permissions.map { |p| ::Authz::PermissionGroups::Assignable.for_permission(p).first.name })
      end

      context 'when the token lacks the read_orbit permission' do
        let(:request_options) { { auth: { personal_access_token: granular_pat(:execute_mcp_tool) } } }

        it_behaves_like 'Orbit tools are not listed'
      end

      context 'when the token has the read_orbit permission' do
        it 'lists the Orbit tools' do
          post_mcp('tools/list', auth: { personal_access_token: granular_pat(:execute_mcp_tool, :read_orbit) })

          expect(listed_orbit_tools.pluck('name')).to contain_exactly('query_graph', 'get_graph_schema')
        end
      end
    end

    context 'when on GitLab.com with the Orbit promo access gate' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(orbit_promo_access_gate: true)
      end

      context 'when the group has no promo add-on and no trial' do
        it_behaves_like 'Orbit tools are not listed'
      end

      context 'when the group has an active orbit_promo add-on' do
        before do
          create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)
        end

        it 'lists the Orbit tools' do
          post_mcp('tools/list')

          expect(listed_orbit_tools.pluck('name')).to contain_exactly('query_graph', 'get_graph_schema')
        end
      end

      context 'when the group has an Orbit trial in progress' do
        before do
          create(:orbit_namespace_enrollment, namespace: group)
        end

        it 'lists the Orbit tools' do
          post_mcp('tools/list')

          expect(listed_orbit_tools.pluck('name')).to contain_exactly('query_graph', 'get_graph_schema')
        end
      end

      context 'when the group trial has ended' do
        before do
          create(:orbit_namespace_enrollment, namespace: group, trial_ended_at: 1.day.ago)
        end

        it_behaves_like 'Orbit tools are not listed'
      end
    end

    context 'when the Orbit server returns the command list as formatted text' do
      before do
        allow(grpc_client).to receive(:list_agent_commands).and_return({ formatted_text: 'query_graph: ...' })
      end

      it 'does not list the Orbit tools', :aggregate_failures do
        post_mcp('tools/list')

        expect(response).to have_gitlab_http_status(:ok)
        expect(listed_orbit_tools).to be_empty
      end
    end

    context 'when the Orbit service is unreachable' do
      before do
        allow(grpc_client).to receive(:list_agent_commands)
          .and_raise(Analytics::KnowledgeGraph::GrpcClient::ConnectionError, 'connection refused')
      end

      it 'still lists the other tools and calls the Orbit server once', :aggregate_failures do
        post_mcp('tools/list', headers: { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => 'all' })

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.dig('result', 'tools')).to be_present
        expect(listed_orbit_tools).to be_empty
        expect(grpc_client).to have_received(:list_agent_commands)
          .once.with(hash_including(timeout: Mcp::Tools::Orbit::CommandCatalog::LIST_COMMANDS_TIMEOUT))
      end
    end
  end

  describe 'tools/call' do
    let(:query) { 'MATCH (p:Project) RETURN p.id LIMIT 5' }

    before do
      allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for).and_call_original
    end

    def call_tool(name, arguments = nil, **options)
      post_mcp('tools/call', params: { name: name, arguments: arguments }.compact, headers: {}, **options)
    end

    it 'runs query_graph with the JSON-RPC id', :aggregate_failures do
      call_tool('query_graph', { query: query }, id: 7)

      expect(response).to have_gitlab_http_status(:ok)
      expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new).once
      expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for).with(
        query: query, user: user, format: :llm, mcp_id: 7,
        request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP)
      )
    end

    context 'with a query runner response' do
      let(:envelope) do
        { jsonrpc: '2.0', result: { content: [{ type: 'text', text: 'rows' }], isError: false }, id: 7 }
      end

      let(:orbit_runner_response) do
        Analytics::KnowledgeGraph::QueryRunner::Response.new(
          status: 200, content_type: 'application/json', body: "#{envelope.to_json}\n"
        )
      end

      it 'renders the query runner response', :aggregate_failures do
        call_tool('query_graph', { query: query }, id: 7)

        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new).once
          .with(hash_including('Query' => query, 'McpId' => 7), user: user, env: anything)
        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers['Gitlab-Workhorse-Send-Data']).to be_nil
        expect(json_response).to eq(envelope.deep_stringify_keys)
      end
    end

    context 'with a failed query runner response' do
      let(:orbit_runner_response) do
        Analytics::KnowledgeGraph::QueryRunner::McpRenderer.new(7).query_error('compile_error', 'unknown entity', nil)
      end

      it 'logs the failure and renders the response unchanged', :aggregate_failures do
        logger = instance_double(Gitlab::Mcp::Logger, conditional_info: nil)
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)

        call_tool('query_graph', { query: query }, id: 7)

        expect(logger).to have_received(:conditional_info)
          .with(user, hash_including(event_name: 'tools_call', tool_name: 'query_graph', tool_status: 'bad_request'))
        expect(response.body).to eq(orbit_runner_response.body)
      end
    end

    it 'logs an ok tool_status for a successful query', :aggregate_failures do
      logger = instance_double(Gitlab::Mcp::Logger, conditional_info: nil)
      allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)

      call_tool('query_graph', { query: query })

      expect(logger).to have_received(:conditional_info)
        .with(user, hash_including(event_name: 'tools_call', tool_name: 'query_graph', tool_status: 'ok'))
    end

    it 'labels query_graph from an ai_workflows token as Duo Workflow traffic' do
      dws_token = create(:oauth_access_token, user: user, scopes: [:mcp, :ai_workflows])

      call_tool('query_graph', { query: query }, auth: { oauth_access_token: dws_token })

      expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:params_for).with(
        hash_including(request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::DWS))
      )
    end

    it 'returns a tool error when query_graph has no query', :aggregate_failures do
      call_tool('query_graph')

      expect(json_response['result']).to include(
        'content' => [{ 'type' => 'text', 'text' => 'Validation error: query is missing' }], 'isError' => true
      )
      expect(Analytics::KnowledgeGraph::QueryRunner).not_to have_received(:new)
    end

    it 'returns the billing namespace contract when the user must pick one', :aggregate_failures do
      allow(Analytics::KnowledgeGraph::GoverningNamespaceGuard).to receive(:ensure_selected!)
        .and_raise(Analytics::KnowledgeGraph::GoverningNamespaceGuard::RequiredError.new([group]))

      call_tool('query_graph', { query: query })

      expect(json_response['result']).to include('isError' => true)
      expect(json_response.dig('result', 'structuredContent', 'error'))
        .to eq(Analytics::KnowledgeGraph::GoverningNamespaceError.new([group]).as_json.deep_stringify_keys)
    end

    it 'returns other commands from InvokeAgentCommand', :aggregate_failures do
      allow(grpc_client).to receive(:invoke_agent_command).and_return({ formatted_text: 'schema text' })

      call_tool('get_graph_schema')

      expect(json_response['result']).to include(
        'content' => [{ 'type' => 'text', 'text' => 'schema text' }], 'isError' => false
      )
      expect(grpc_client).to have_received(:invoke_agent_command).with(
        command_name: 'get_graph_schema', parameters: {}, user: user,
        request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP)
      )
    end

    describe 'when the Orbit server returns an error' do
      def raise_grpc_error(code)
        allow(grpc_client).to receive(:invoke_agent_command).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'invoke_agent_command failed: 10.0.0.1:50054 (3)', grpc_code: code, grpc_details: 'bad parameters'
          )
        )
      end

      it 'returns the error details for a client error' do
        raise_grpc_error(GRPC::Core::StatusCodes::INVALID_ARGUMENT)

        call_tool('get_graph_schema', {})

        expect(json_response['result']).to include(
          'content' => [{ 'type' => 'text', 'text' => 'bad parameters' }], 'isError' => true
        )
      end

      it 'returns a generic error for a server error' do
        raise_grpc_error(GRPC::Core::StatusCodes::UNAVAILABLE)

        call_tool('get_graph_schema', {})

        expect(json_response['result']).to include(
          'content' => [{ 'type' => 'text', 'text' => 'Orbit request failed' }], 'isError' => true
        )
      end
    end

    it 'returns a rate limit error when query_graph is throttled', :aggregate_failures do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_call_original
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
        .with(anything, user, :orbit_query, hash_including(scope: { user: user })).and_return(true)

      call_tool('query_graph', { query: query })

      expect(json_response['result']).to include('isError' => true)
      expect(json_response.dig('result', 'structuredContent', 'error', 'type')).to eq('rate_limited')
      expect(Analytics::KnowledgeGraph::QueryRunner).not_to have_received(:new)
    end

    shared_examples 'Orbit tool calls are rejected' do
      it 'rejects the call as an unknown tool', :aggregate_failures do
        call_tool('query_graph', { query: query }, **request_options)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response.dig('error', 'data', 'params')).to eq("Tool 'query_graph' not found.")
        expect(Analytics::KnowledgeGraph::QueryRunner).not_to have_received(:new)
        expect(grpc_client).not_to have_received(:list_agent_commands)
      end
    end

    context 'when the user has no Orbit-enabled group' do
      before do
        Analytics::KnowledgeGraph::EnabledNamespace.delete_all
      end

      it_behaves_like 'Orbit tool calls are rejected'
    end

    context 'when the instance license does not include Orbit' do
      before do
        stub_licensed_features(orbit: false)
      end

      it_behaves_like 'Orbit tool calls are rejected'
    end

    context 'when a granular personal access token lacks the read_orbit permission' do
      let(:request_options) do
        token = create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
          permissions: [::Authz::PermissionGroups::Assignable.for_permission(:execute_mcp_tool).first.name])

        { auth: { personal_access_token: token } }
      end

      it_behaves_like 'Orbit tool calls are rejected'
    end
  end

  describe 'Duo Workflow MCP config' do
    it 'keeps the Orbit tools out of the static tool list while Orbit is available', :aggregate_failures do
      expect(Mcp::Tools::Manager.new.list_tools.keys).not_to include('query_graph', 'get_graph_schema')
      expect(grpc_client).not_to have_received(:list_agent_commands)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
