# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::Data, :clean_gitlab_redis_rate_limiting, feature_category: :knowledge_graph do
  include_context 'with a stubbed Orbit query runner'

  let_it_be_with_reload(:user) { create(:user) }

  let(:rest_context) { having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::REST) }
  let(:frontend_context) { having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::FRONTEND) }
  let(:code_intelligence_context) do
    having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::CODE_INTELLIGENCE)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  shared_examples 'requires authentication' do
    context 'when not authenticated' do
      it 'returns 401' do
        send_request(user: nil)

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end
  end

  shared_examples 'requires :orbit licensed feature' do
    context 'when :orbit licensed feature is not available' do
      before do
        stub_licensed_features(orbit: false)
      end

      it 'returns 403' do
        send_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end

  shared_examples 'accepts the GQL response format' do
    it 'forwards gql' do
      send_request(request_params: params.merge(response_format: 'gql'))

      expect(orbit_query_params.last['Format']).to eq('gql')
    end
  end

  shared_examples 'maps gRPC error codes to HTTP statuses' do |grpc_method|
    using RSpec::Parameterized::TableSyntax

    where(:grpc_code, :http_status) do
      GRPC::Core::StatusCodes::DEADLINE_EXCEEDED | :gateway_timeout
      GRPC::Core::StatusCodes::PERMISSION_DENIED | :not_found
      GRPC::Core::StatusCodes::INVALID_ARGUMENT  | :bad_request
      GRPC::Core::StatusCodes::NOT_FOUND         | :not_found
      GRPC::Core::StatusCodes::UNAVAILABLE       | :service_unavailable
      GRPC::Core::StatusCodes::INTERNAL          | :internal_server_error
    end

    with_them do
      before do
        allow(grpc_client).to receive(grpc_method)
          .and_raise(Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new('boom', grpc_code: grpc_code))
      end

      it 'returns the mapped status and echoes the gRPC code header', :aggregate_failures do
        send_request

        expect(response).to have_gitlab_http_status(http_status)
        expect(response.headers['X-GKG-Grpc-Code']).to eq(grpc_code.to_s)
        expect(json_response).to eq('code' => grpc_code, 'message' => 'Orbit request failed')
      end
    end
  end

  shared_context 'with governing namespace candidates' do
    let_it_be(:candidate_a) { create(:group, name: 'candidate-a') }
    let_it_be(:candidate_b) { create(:group, name: 'candidate-b') }

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
    end
  end

  shared_examples 'requires a governing namespace' do
    include_context 'with governing namespace candidates'

    context 'when the preference is unset and several candidates exist' do
      it 'returns 422 with the governing namespace contract', :aggregate_failures do
        send_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq(
          'code' => 'billing_namespace_required',
          'message' => s_('Orbit|Select a default group in your preferences to run GitLab Orbit queries.'),
          'deep_link' => Gitlab::Routing.url_helpers.profile_preferences_url,
          'candidates' => [
            { 'id' => candidate_a.id, 'name' => 'candidate-a' },
            { 'id' => candidate_b.id, 'name' => 'candidate-b' }
          ]
        )
      end
    end

    context 'when no candidates exist' do
      let(:governing_namespace_candidates) { [] }

      it 'returns 422 with an empty candidates list', :aggregate_failures do
        send_request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to include('code' => 'billing_namespace_required', 'candidates' => [])
      end
    end

    context 'when exactly one candidate exists' do
      let(:governing_namespace_candidates) { [candidate_a] }
      let(:single_candidate_fallback) { candidate_a }

      it 'executes the query' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the preference is set' do
      before do
        allow(governing_namespace_finder).to receive(:eligible?).with(candidate_a.id).and_return(true)
        user.user_preference.update!(knowledge_graph_governing_namespace_id: candidate_a.id)
      end

      it 'executes the query' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when knowledge_graph_billing is disabled' do
      before do
        stub_feature_flags(knowledge_graph_billing: false)
      end

      it 'executes the query' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  shared_context 'with an instance license but no trial or purchase' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: true)
    end
  end

  describe 'POST /orbit/query' do
    let(:current_user) { user }
    let(:query) { 'MATCH (mr:MergeRequest) RETURN mr LIMIT 10' }
    let(:params) { { query: query } }
    let(:endpoint) { 'localhost:50054' }
    let(:jwt_token) { 'test-jwt-token' }

    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:configured_endpoint).and_return(endpoint)
      allow(Analytics::KnowledgeGraph::SourceType).to receive(:for_orbit_request)
        .and_return(Analytics::KnowledgeGraph::SourceType::REST)
      allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
        .with(user: user, request_context: rest_context)
        .and_return(jwt_token)
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:secure_channel?).with(endpoint).and_return(false)

      auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true)
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
    end

    def send_request(user: self.user, request_params: params)
      post api('/orbit/query', user), params: request_params
    end

    include_examples 'requires authentication'
    include_examples 'requires :orbit licensed feature'
    include_examples 'accepts the GQL response format'

    it_behaves_like 'requires a governing namespace'

    context 'with an instance license but no trial or purchase' do
      include_context 'with an instance license but no trial or purchase'

      it 'returns 403' do
        send_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    it 'sends the credential type to Orbit' do
      send_request

      expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
        .with(user: user, request_context: having_attributes(token_type: 'personal_access_token'))
    end

    it_behaves_like 'authorizing granular token permissions', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) do
        post api('/orbit/query', personal_access_token: pat), params: params
      end
    end

    context 'with a fine-grained token that holds the deprecated read_knowledge_graph permission' do
      let(:old_pat) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
          permissions: ['read_knowledge_graph'])
      end

      it 'denies Orbit access' do
        post api('/orbit/query', personal_access_token: old_pat), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['error']).to eq('insufficient_granular_scope')
      end

      it 'keeps the token rotatable' do
        result = PersonalAccessTokens::RotateService.new(user, old_pat).execute

        expect(result).to be_success
        expect(result.payload[:personal_access_token].granular_scopes.first.permissions)
          .to eq(['read_knowledge_graph'])
      end
    end

    context 'with OAuth token scope' do
      where(:description, :auth_setup, :expected_status) do
        [
          ['read_api OAuth token', -> { create(:oauth_access_token, user: user, scopes: [:read_api]) }, :ok],
          ['api OAuth token', -> { create(:oauth_access_token, user: user, scopes: [:api]) }, :ok],
          ['ai_workflows OAuth token', -> { create(:oauth_access_token, user: user, scopes: [:ai_workflows]) }, :ok],
          ['read_user OAuth token (insufficient)', -> { create(:oauth_access_token, user: user, scopes: [:read_user]) },
            :forbidden]
        ]
      end

      with_them do
        it 'enforces access control correctly' do
          token = instance_exec(&auth_setup)
          post api('/orbit/query', oauth_access_token: token), params: params

          # A read_api-scoped token must not be rejected with 403 insufficient_scope.
          # The exact success status depends on namespace/FF configuration, but the
          # scope check must pass (i.e. not return forbidden due to insufficient scope).
          if expected_status == :ok
            expect(response).not_to have_gitlab_http_status(:forbidden)
          else
            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end
      end
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
      def request
        post api('/orbit/query', current_user), params: params
      end
    end

    context 'with the Orbit query limit set in the application settings', :freeze_time do
      before do
        stub_application_setting(orbit_query_limit: 1)
      end

      it 'throttles the user after the limit' do
        2.times { post api('/orbit/query', user), params: params }

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end

      it 'does not throttle a user in the Orbit rate limit allowlist' do
        stub_application_setting(orbit_rate_limit_allowlist: [user.username])

        2.times { post api('/orbit/query', user), params: params }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'with GQL text' do
      using RSpec::Parameterized::TableSyntax

      let(:query) { " MATCH (u:User {name: 'Zoë \\\"雪\\\"'}) RETURN u LIMIT 1\n" }

      where(:format) { %w[raw llm] }

      with_them do
        it 'preserves the query and response format', :aggregate_failures do
          post api('/orbit/query', user),
            params: Gitlab::Json.dump(query: query, response_format: format),
            headers: { 'CONTENT_TYPE' => 'application/json', 'X-Gitlab-Orbit-Query-Language' => 'untrusted' }

          expect(response).to have_gitlab_http_status(:ok)
          decoded = orbit_query_params.last
          expect(decoded['Query']).to eq(query)
          expect(decoded['QueryType']).to be_nil
          expect(decoded['Language']).to eq('gql')
          expect(decoded.dig('GkgServer', 'headers')).not_to have_key('x-gitlab-orbit-query-language')
          expect(decoded['Format']).to eq(format)
        end
      end
    end

    it 'rejects a JSON object query' do
      post api('/orbit/query', user),
        params: Gitlab::Json.dump(query: { nodes: ['User'] }),
        headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]).to be_nil
    end

    context 'when authenticated' do
      it 'passes the Orbit query params to the query runner' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(Analytics::KnowledgeGraph::QueryRunner).to have_received(:new).with(anything, user: user, env: anything)

        params = orbit_query_params.last
        expect(params).to include(
          'GkgServer' => a_hash_including(
            'address' => endpoint,
            'headers' => a_hash_including('authorization' => "Bearer #{jwt_token}")
          ),
          'Query' => query,
          'Format' => 'raw'
        )
      end

      it 'supports llm response format' do
        send_request(request_params: params.merge(response_format: 'llm'))

        expect(response).to have_gitlab_http_status(:ok)

        params = orbit_query_params.last
        expect(params['Format']).to eq('llm')
      end

      it 'forwards User-Agent in the Orbit headers' do
        post api('/orbit/query', user), params: params, headers: { 'User-Agent' => 'TestAgent/1.0' }

        expect(response).to have_gitlab_http_status(:ok)
        decoded_params = orbit_query_params.last
        expect(decoded_params.dig('GkgServer', 'headers')).to include('x-client-user-agent' => 'TestAgent/1.0')
      end

      context 'with a query runner response' do
        let(:runner_response) do
          Analytics::KnowledgeGraph::QueryRunner::Response.new(
            status: 200, content_type: 'application/json', body: %({"result":[],"query_type":"search","row_count":0}\n)
          )
        end

        let(:orbit_runner_response) { runner_response }

        it 'renders the query runner response', :aggregate_failures do
          send_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.media_type).to eq('application/json')
          expect(response.body).to eq(runner_response.body)
          expect(response.headers[::Gitlab::Workhorse::SEND_DATA_HEADER]).to be_nil
          expect(response.headers['ETag']).not_to eq(%(W/"#{Digest::SHA256.hexdigest(response.body)[0, 32]}"))
        end

        context 'with a streamed body' do
          let(:stream_body) { instance_double(Analytics::KnowledgeGraph::QueryRunner::StreamBody, close: nil) }
          let(:runner_response) do
            Analytics::KnowledgeGraph::QueryRunner::Response.new(
              status: 200, content_type: 'application/json', body: stream_body
            )
          end

          before do
            allow(stream_body).to receive(:each).and_yield('{"result":').and_yield('[]').and_yield("}\n")
          end

          it 'streams the body parts in order and closes the body', :aggregate_failures do
            send_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(response.media_type).to eq('application/json')
            expect(response.body).to eq(%({"result":[]}\n))
            expect(stream_body).to have_received(:close)
          end
        end
      end

      context 'when query param is missing' do
        it 'returns 400' do
          send_request(request_params: {})

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when JWT generation raises AuthorizationError' do
        before do
          allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
            .and_raise(Analytics::KnowledgeGraph::GrpcClient::AuthorizationError, 'JWT generation failed')
        end

        it 'returns 503' do
          send_request

          expect(response).to have_gitlab_http_status(:service_unavailable)
        end
      end

      context 'when user has no enabled namespaces' do
        before do
          auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext)
          allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new)
            .with(user).and_return(auth_context)
          allow(auth_context).to receive(:has_enabled_namespaces?).and_return(false)
        end

        it 'returns 403' do
          send_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end

      context 'with source_type param' do
        before do
          allow(Analytics::KnowledgeGraph::SourceType).to receive(:for_orbit_request).and_call_original
        end

        context 'when request is CSRF-authenticated and source_type is code_intelligence' do
          before do
            allow(Analytics::KnowledgeGraph::SourceType).to receive(:frontend_request?).and_return(true)
            allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
              .with(user: user, request_context: code_intelligence_context)
              .and_return(jwt_token)
          end

          it 'passes code_intelligence to the query runner' do
            send_request(request_params: params.merge(source_type: 'code_intelligence'))

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
              .with(user: user, request_context: code_intelligence_context)
          end
        end

        context 'when request is not CSRF-authenticated and source_type is code_intelligence' do
          before do
            allow(Analytics::KnowledgeGraph::SourceType).to receive(:frontend_request?).and_return(false)
          end

          it 'ignores the param and falls back to rest' do
            send_request(request_params: params.merge(source_type: 'code_intelligence'))

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
              .with(user: user, request_context: rest_context)
          end
        end

        context 'when request is CSRF-authenticated and source_type is not in FRONTEND_SUBTYPES' do
          before do
            allow(Analytics::KnowledgeGraph::SourceType).to receive(:frontend_request?).and_return(true)
            allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
              .with(user: user, request_context: frontend_context)
              .and_return(jwt_token)
          end

          it 'falls back to frontend' do
            send_request(request_params: params.merge(source_type: 'mcp'))

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
              .with(user: user, request_context: frontend_context)
          end
        end
      end
    end
  end

  describe 'POST /orbit/query/:name' do
    let(:current_user) { user }
    let(:query_name) { 'expand_neighbors' }
    let(:params) { { parameters: { entity: 'User', node_ids: [1], limit: 50 } } }
    let(:endpoint) { 'localhost:50054' }
    let(:jwt_token) { 'test-jwt-token' }

    before do
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:configured_endpoint).and_return(endpoint)
      allow(Analytics::KnowledgeGraph::SourceType).to receive(:for_orbit_request)
        .and_return(Analytics::KnowledgeGraph::SourceType::REST)
      allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
        .with(user: user, request_context: rest_context)
        .and_return(jwt_token)
      allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:secure_channel?).with(endpoint).and_return(false)

      auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true)
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
    end

    def send_request(user: self.user, request_params: params)
      post api("/orbit/query/#{query_name}", user),
        params: request_params.to_json,
        headers: { 'CONTENT_TYPE' => 'application/json' }
    end

    include_examples 'requires authentication'
    include_examples 'requires :orbit licensed feature'
    include_examples 'accepts the GQL response format'

    it_behaves_like 'requires a governing namespace'

    it_behaves_like 'authorizing granular token permissions', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) do
        post api("/orbit/query/#{query_name}", personal_access_token: pat),
          params: params.to_json,
          headers: { 'CONTENT_TYPE' => 'application/json' }
      end
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
      def request
        post api("/orbit/query/#{query_name}", current_user),
          params: params.to_json,
          headers: { 'CONTENT_TYPE' => 'application/json' }
      end
    end

    context 'when authenticated' do
      it 'passes the named query envelope to the query runner' do
        send_request

        expect(response).to have_gitlab_http_status(:ok)

        decoded = orbit_query_params.last
        expect(decoded).to include(
          'GkgServer' => a_hash_including(
            'address' => endpoint,
            'headers' => a_hash_including('authorization' => "Bearer #{jwt_token}")
          ),
          'Query' => { name: 'expand_neighbors',
                       parameters: { entity: 'User', node_ids: [1], limit: 50 } }.to_json,
          'QueryType' => 'named',
          'Format' => 'raw'
        )
      end

      it 'defaults parameters to an empty object' do
        send_request(request_params: {})

        expect(response).to have_gitlab_http_status(:ok)

        decoded = orbit_query_params.last
        expect(decoded['Query']).to eq({ name: 'expand_neighbors', parameters: {} }.to_json)
      end

      it 'supports llm response format' do
        send_request(request_params: params.merge(response_format: 'llm'))

        expect(response).to have_gitlab_http_status(:ok)

        decoded = orbit_query_params.last
        expect(decoded['Format']).to eq('llm')
      end

      context 'when the request body is form-encoded' do
        it 'returns 400 telling the caller to send JSON' do
          post api("/orbit/query/#{query_name}", user), params: params

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('JSON request body required')
        end
      end

      context 'with source_type param' do
        before do
          allow(Analytics::KnowledgeGraph::SourceType).to receive(:for_orbit_request).and_call_original
        end

        context 'when request is CSRF-authenticated and source_type is code_intelligence' do
          before do
            allow(Analytics::KnowledgeGraph::SourceType).to receive(:frontend_request?).and_return(true)
            allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token)
              .with(user: user, request_context: code_intelligence_context)
              .and_return(jwt_token)
          end

          it 'passes code_intelligence to the query runner' do
            send_request(request_params: params.merge(source_type: 'code_intelligence'))

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
              .with(user: user, request_context: code_intelligence_context)
          end
        end

        context 'when request is not CSRF-authenticated and source_type is code_intelligence' do
          before do
            allow(Analytics::KnowledgeGraph::SourceType).to receive(:frontend_request?).and_return(false)
          end

          it 'ignores the param and falls back to rest' do
            send_request(request_params: params.merge(source_type: 'code_intelligence'))

            expect(response).to have_gitlab_http_status(:ok)
            expect(Analytics::KnowledgeGraph::JwtAuth).to have_received(:generate_token)
              .with(user: user, request_context: rest_context)
          end
        end
      end

      context 'when user has no enabled namespaces' do
        before do
          auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext)
          allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new)
            .with(user).and_return(auth_context)
          allow(auth_context).to receive(:has_enabled_namespaces?).and_return(false)
        end

        it 'returns 403' do
          send_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end
  end

  describe 'OpenAPI metadata' do
    let(:published_routes) do
      described_class.routes.reject { |route| route.settings.dig(:description, :hidden) }
    end

    it 'publishes only the documented endpoints' do
      published = published_routes.map { |route| "#{route.request_method} #{route.origin}" }

      expect(published).to match_array([
        'POST /api/:version/orbit/context',
        'POST /api/:version/orbit/query',
        'POST /api/:version/orbit/query/:name',
        'GET /api/:version/orbit/skills',
        'GET /api/:version/orbit/skills/:name',
        'GET /api/:version/orbit/skills/:name/*path'
      ])
    end

    it 'annotates every published endpoint for the API reference', :aggregate_failures do
      experimental_paths = ["/orbit/context(.:format)"]
      experimental_routes, generally_available_routes = published_routes.partition do |route|
        experimental_paths.any? { |path| route.path.end_with?(path) }
      end

      expect(experimental_routes.map { |route| route.settings[:lifecycle] }).to all(eq(:experiment))
      expect(experimental_routes.size).to eq(1)
      expect(generally_available_routes.map { |route| route.settings[:lifecycle] }).to all(be_nil)
      expect(published_routes.map { |route| route.settings.dig(:description, :tags) }).to all(eq(%w[orbit]))
    end

    it 'marks every hidden endpoint as experimental' do
      hidden_routes = described_class.routes.select { |route| route.settings.dig(:description, :hidden) }

      expect(hidden_routes).not_to be_empty
      expect(hidden_routes.map { |route| route.settings[:lifecycle] }).to all(eq(:experiment))
    end
  end
end
