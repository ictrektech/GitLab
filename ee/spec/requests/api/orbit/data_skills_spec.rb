# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::Data, :clean_gitlab_redis_rate_limiting, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }

  let_it_be(:enabled_group) { create(:group) }
  let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: enabled_group) }

  let(:current_user) { user }
  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:skill_summary) do
    {
      'name' => 'orbit',
      'version' => '0.29.0',
      'compatibility' => 'Orbit CLI',
      'description' => 'Use the glab orbit CLI.'
    }
  end

  let(:skill_tree) do
    skill_summary.except('description').merge(
      'server_version' => '0.31.0',
      'files' => [
        {
          'path' => 'SKILL.md',
          'sha256' => 'file-sha',
          'content' => "# Orbit skill\n"
        }
      ]
    )
  end

  before_all { enabled_group.add_reporter(user) }

  before do
    stub_config(knowledge_graph: { 'enabled' => true })
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(Analytics::KnowledgeGraph::SourceType).to receive(:for_orbit_request)
      .and_return(Analytics::KnowledgeGraph::SourceType::REST)
    allow(grpc_client).to receive(:list_skills)
      .and_return({ 'skills' => [skill_summary], 'server_version' => '0.31.0' })
    allow(grpc_client).to receive(:get_skill) do |metadata_only:, **|
      metadata_only ? skill_tree.except('files') : skill_tree
    end
  end

  context 'when the knowledge graph service is not configured' do
    before do
      stub_config(knowledge_graph: { 'enabled' => false })
    end

    it 'returns 404 without calling the GKG', :aggregate_failures do
      [
        '/orbit/skills',
        '/orbit/skills/orbit',
        '/orbit/skills/orbit/SKILL.md'
      ].each do |path|
        get api(path, user)

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to eq('Skills are not available')
      end

      expect(grpc_client).not_to have_received(:list_skills)
      expect(grpc_client).not_to have_received(:get_skill)
    end
  end

  context 'when the user has no Orbit-enabled namespaces' do
    let(:paths) { ['/orbit/skills', '/orbit/skills/orbit', '/orbit/skills/orbit/SKILL.md'] }

    shared_examples 'skills are not available' do
      it 'returns 404 without calling the GKG', :aggregate_failures do
        paths.each do |path|
          get api(path, requesting_user)

          expect(response).to have_gitlab_http_status(:not_found)
          expect(json_response['message']).to eq('Skills are not available')
        end

        head api('/orbit/skills/orbit', requesting_user)
        expect(response).to have_gitlab_http_status(:not_found)

        get api('/orbit/skills/orbit', requesting_user), headers: { 'If-None-Match' => '"0.29.0"' }
        expect(response).to have_gitlab_http_status(:not_found)

        expect(grpc_client).not_to have_received(:list_skills)
        expect(grpc_client).not_to have_received(:get_skill)
      end
    end

    context 'with a user who is not a member of any group' do
      let(:requesting_user) { create(:user) }

      it_behaves_like 'skills are not available'
    end

    context 'with a reporter in a group that is not Orbit-enabled' do
      let(:requesting_user) { create(:user, reporter_of: create(:group)) }

      it_behaves_like 'skills are not available'
    end

    context 'with a guest in an Orbit-enabled group' do
      let(:requesting_user) { create(:user, guest_of: enabled_group) }

      it_behaves_like 'skills are not available'
    end
  end

  context 'when the user has Orbit-enabled namespaces through a subgroup' do
    let(:subgroup_user) { create(:user, reporter_of: create(:group, parent: enabled_group)) }

    it 'serves the skills', :aggregate_failures do
      get api('/orbit/skills', subgroup_user)
      expect(response).to have_gitlab_http_status(:ok)

      get api('/orbit/skills/orbit', subgroup_user)
      expect(response).to have_gitlab_http_status(:ok)

      get api('/orbit/skills/orbit/SKILL.md', subgroup_user)
      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'when the user is an admin without Orbit-enabled namespaces' do
    it 'serves the skills' do
      get api('/orbit/skills', create(:admin), admin_mode: true)

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'GET /orbit/skills' do
    it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
      def request
        get api('/orbit/skills', current_user)
      end
    end

    def send_request(user: self.user, headers: {}, **options)
      get api('/orbit/skills', user, **options), headers: headers
    end

    it_behaves_like 'authorizing granular token permissions', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) { get api('/orbit/skills', personal_access_token: pat) }
    end

    it 'returns deployed skill summaries with a stable collection ETag', :aggregate_failures do
      second_skill = skill_summary.merge('name' => 'another', 'version' => '0.30.0')
      allow(grpc_client).to receive(:list_skills)
        .and_return({ 'skills' => [skill_summary, second_skill], 'server_version' => '0.31.0' })
      pairs = [%w[another 0.30.0], %w[orbit 0.29.0]]
      expected_etag = %("#{Digest::SHA256.hexdigest(Gitlab::Json.generate(pairs))}")
      expect(grpc_client).not_to receive(:invoke_agent_command)

      send_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq('skills' => [skill_summary, second_skill], 'server_version' => '0.31.0')
      expect(response.headers).to include(
        'ETag' => expected_etag,
        'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:list_skills).with(
        hash_including(user: user)
      )
    end

    ['%s', 'W/%s', '"stale", W/%s', '*'].each do |validator|
      it "returns 304 for a matching collection validator #{validator.inspect}", :aggregate_failures do
        send_request
        etag = response.headers['ETag']

        send_request(headers: { 'If-None-Match' => validator.gsub('%s', etag) })

        expect(response).to have_gitlab_http_status(:not_modified)
        expect(response.body).to be_empty
        expect(response.headers).to include(
          'ETag' => etag,
          'Cache-Control' => 'private, max-age=0, must-revalidate'
        )
        expect(grpc_client).to have_received(:list_skills).twice
      end
    end

    it 'keeps the collection ETag stable across changes to deployment metadata' do
      send_request
      etag = response.headers['ETag']

      allow(grpc_client).to receive(:list_skills).and_return(
        'skills' => [skill_summary.merge('compatibility' => 'Updated requirements')],
        'server_version' => '0.32.0'
      )
      send_request

      expect(response.headers['ETag']).to eq(etag)
    end

    it 'returns 404 when the GKG does not support skill RPCs' do
      allow(grpc_client).to receive(:list_skills).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'list_skills failed', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )

      send_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response['message']).to eq('Skills are not available')
    end

    it 'allows a read_api OAuth token' do
      token = create(:oauth_access_token, user: user, scopes: [:read_api])

      get api('/orbit/skills', oauth_access_token: token)

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns 401 without authentication' do
      send_request(user: nil)

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it 'does not require Orbit entitlement' do
      stub_licensed_features(orbit: false)

      send_request

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'GET /orbit/skills/:name' do
    it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
      def request
        get api('/orbit/skills/orbit', current_user)
      end
    end

    def send_request(user: self.user, headers: {}, **options)
      get api('/orbit/skills/orbit', user, **options), headers: headers
    end

    it_behaves_like 'authorizing granular token permissions', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) { get api('/orbit/skills/orbit', personal_access_token: pat) }
    end

    it 'returns the complete skill tree with cache headers', :aggregate_failures do
      send_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(skill_tree)
      expect(response.headers).to include(
        'ETag' => '"0.29.0"',
        'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:get_skill).with(
        hash_including(name: 'orbit', metadata_only: false, user: user)
      )
    end

    it 'returns 304 from a metadata-only call when If-None-Match matches', :aggregate_failures do
      send_request(headers: { 'If-None-Match' => '"0.29.0"' })

      expect(response).to have_gitlab_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(response.headers).to include(
        'ETag' => '"0.29.0"',
        'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:get_skill).once.with(
        hash_including(name: 'orbit', metadata_only: true)
      )
      expect(grpc_client).not_to have_received(:get_skill).with(
        hash_including(name: 'orbit', metadata_only: false)
      )
    end

    ['W/"0.29.0"', '"stale", W/"0.29.0"'].each do |validator|
      it "returns 304 for If-None-Match #{validator.inspect} using only metadata" do
        send_request(headers: { 'If-None-Match' => validator })

        expect(response).to have_gitlab_http_status(:not_modified)
        expect(response.body).to be_empty
        expect(grpc_client).to have_received(:get_skill).once.with(
          hash_including(name: 'orbit', metadata_only: true)
        )
      end
    end

    it 'fetches the full tree after stale conditional metadata' do
      send_request(headers: { 'If-None-Match' => '"stale"' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(skill_tree)
      expect(grpc_client).to have_received(:get_skill).with(
        hash_including(name: 'orbit', metadata_only: true)
      )
      expect(grpc_client).to have_received(:get_skill).with(
        hash_including(name: 'orbit', metadata_only: false)
      )
    end

    it 'returns 404 with the GKG details and known skill names' do
      details = 'Unknown skill "missing". Known skills: ["orbit"]'
      error = Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
        "get_skill failed: 5:#{details} (5)",
        grpc_code: GRPC::Core::StatusCodes::NOT_FOUND,
        grpc_details: details
      )
      allow(grpc_client).to receive(:get_skill)
        .with(hash_including(name: 'missing'))
        .and_raise(error)

      get api('/orbit/skills/missing', user)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response['message']).to eq(details)
    end

    [nil, '', '  '].each do |details|
      it "returns a generic 404 when the GKG supplies blank skill details (#{details.inspect})" do
        allow(grpc_client).to receive(:get_skill).and_raise(
          Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
            'get_skill failed: 5:raw gRPC error (5)',
            grpc_code: GRPC::Core::StatusCodes::NOT_FOUND,
            grpc_details: details
          )
        )

        send_request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['message']).to eq('Skill not found')
      end
    end

    it 'returns 404 when the GKG does not support skill RPCs' do
      allow(grpc_client).to receive(:get_skill).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'get_skill failed', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )

      send_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response['message']).to eq('Skills are not available')
    end

    it 'uses the generic gRPC error mapping for other connection errors', :aggregate_failures do
      error = Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
        'service unavailable',
        grpc_code: GRPC::Core::StatusCodes::UNAVAILABLE
      )
      allow(grpc_client).to receive(:get_skill)
        .with(hash_including(name: 'orbit'))
        .and_raise(error)

      send_request

      expect(response).to have_gitlab_http_status(:service_unavailable)
      expect(response.headers['X-GKG-Grpc-Code']).to eq(GRPC::Core::StatusCodes::UNAVAILABLE.to_s)
      expect(json_response).to eq(
        'code' => GRPC::Core::StatusCodes::UNAVAILABLE,
        'message' => 'Orbit request failed'
      )
    end
  end

  describe 'GET /orbit/skills/:name/*path' do
    let(:skill_tree) do
      super().merge('files' => super()['files'] + [
        { 'path' => 'references/usage.md', 'sha256' => 'nested-sha', 'content' => "# Usage\n" },
        { 'path' => 'scripts/setup.sh', 'sha256' => 'script-sha', 'content' => "echo ready\n" }
      ])
    end

    def file_request(path = 'SKILL.md', user: self.user, headers: {}, method: :get, **options)
      public_send(method, api("/orbit/skills/orbit/#{path}", user, **options), headers: headers)
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
      def request
        get api('/orbit/skills/orbit/SKILL.md', current_user)
      end
    end

    it_behaves_like 'authorizing granular token permissions', :read_orbit do
      let(:boundary_object) { :user }
      let(:request) { get api('/orbit/skills/orbit/SKILL.md', personal_access_token: pat) }
    end

    it 'returns SKILL.md as raw markdown with a strong file ETag', :aggregate_failures do
      file_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to eq("# Orbit skill\n")
      expect(response.media_type).to eq('text/markdown')
      expect(response.headers).to include(
        'ETag' => '"file-sha"', 'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:get_skill).with(hash_including(name: 'orbit', metadata_only: false))
    end

    it 'returns nested markdown and other text files without HTML interpretation', :aggregate_failures do
      file_request('references/usage.md')
      expect(response.body).to eq("# Usage\n")
      expect(response.media_type).to eq('text/markdown')
      expect(response.headers['ETag']).to eq('"nested-sha"')

      file_request('scripts/setup.sh')
      expect(response.body).to eq("echo ready\n")
      expect(response.media_type).to eq('text/plain')
    end

    it 'does not affect the JSON skill route' do
      get api('/orbit/skills/orbit', user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.media_type).to eq('application/json')
      expect(json_response).to eq(skill_tree)
    end

    ['missing.md', '%252e%252e/SKILL.md'].each do |path|
      it "returns 404 for unknown manifest path #{path.inspect}" do
        file_request(path)

        expect(response).to have_gitlab_http_status(:not_found)
        expect(grpc_client).to have_received(:get_skill)
      end
    end

    ['./SKILL.md', 'references/./usage.md'].each do |path|
      it "rejects dot segment #{path.inspect} before fetching the skill" do
        file_request(path)

        expect(response).to have_gitlab_http_status(:not_found)
        expect(grpc_client).not_to have_received(:get_skill)
      end
    end

    ['../SKILL.md', '%2e%2e/SKILL.md', 'SKILL.md/../SKILL.md'].each do |path|
      it "rejects traversal #{path.inspect} in path traversal middleware" do
        file_request(path)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(grpc_client).not_to have_received(:get_skill)
      end
    end

    it 'accepts repeated slashes normalized by the router as an alias' do
      file_request('references//usage.md')

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to eq("# Usage\n")
    end

    it 'rejects encoded repeated slashes during path validation' do
      file_request('references%2F%2Fusage.md')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(grpc_client).not_to have_received(:get_skill)
    end

    it 'returns 304 with cache headers for a matching file validator' do
      file_request(headers: { 'If-None-Match' => 'W/"file-sha"' })

      expect(response).to have_gitlab_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(response.headers).to include(
        'ETag' => '"file-sha"', 'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
    end

    it 'returns headers but no body for HEAD requests' do
      file_request(method: :head)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to be_empty
      expect(response.headers).to include('ETag' => '"file-sha"')
      expect(response.media_type).to eq('text/markdown')
    end

    it 'returns 304 for conditional HEAD requests' do
      file_request(method: :head, headers: { 'If-None-Match' => '"file-sha"' })

      expect(response).to have_gitlab_http_status(:not_modified)
      expect(response.body).to be_empty
    end

    it 'rate limits HEAD requests' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).with(:orbit_query, any_args).and_return(true)

      file_request(method: :head)

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(grpc_client).not_to have_received(:get_skill)
    end

    it 'returns 404 when the GKG does not implement skill RPCs' do
      allow(grpc_client).to receive(:get_skill).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'get_skill failed', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )

      file_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response['message']).to eq('Skills are not available')
    end

    it 'requires authentication' do
      file_request(user: nil)

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it 'allows read_api OAuth without Orbit entitlement' do
      stub_licensed_features(orbit: false)
      token = create(:oauth_access_token, user: user, scopes: [:read_api])

      file_request(oauth_access_token: token)

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'HEAD /orbit/skills/:name' do
    it 'returns 304 without a body for a matching validator' do
      head api('/orbit/skills/orbit', user), headers: { 'If-None-Match' => '"0.29.0"' }

      expect(response).to have_gitlab_http_status(:not_modified)
      expect(response.body).to be_empty
      expect(response.headers).to include(
        'ETag' => '"0.29.0"',
        'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:get_skill).once.with(
        hash_including(name: 'orbit', metadata_only: true)
      )
    end

    it 'returns 404 without a body for an unknown name' do
      allow(grpc_client).to receive(:get_skill).with(hash_including(name: 'missing')).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'get_skill failed', grpc_code: GRPC::Core::StatusCodes::NOT_FOUND, grpc_details: 'Unknown skill'
        )
      )

      head api('/orbit/skills/missing', user)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(response.body).to be_empty
      expect(grpc_client).to have_received(:get_skill).once.with(
        hash_including(name: 'missing', metadata_only: true)
      )
    end

    it 'returns 404 without a body when the GKG does not support skill RPCs' do
      allow(grpc_client).to receive(:get_skill).and_raise(
        Analytics::KnowledgeGraph::GrpcClient::ConnectionError.new(
          'get_skill failed', grpc_code: GRPC::Core::StatusCodes::UNIMPLEMENTED
        )
      )

      head api('/orbit/skills/orbit', user)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it 'rate limits metadata requests without a response body' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:orbit_query, any_args).and_return(true)

      head api('/orbit/skills/orbit', user)

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(response.body).to be_empty
      expect(grpc_client).not_to have_received(:get_skill)
    end

    it 'returns only headers from a metadata-only call', :aggregate_failures do
      head api('/orbit/skills/orbit', user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to be_empty
      expect(response.headers).to include(
        'ETag' => '"0.29.0"',
        'Cache-Control' => 'private, max-age=0, must-revalidate'
      )
      expect(grpc_client).to have_received(:get_skill).once.with(
        hash_including(name: 'orbit', metadata_only: true)
      )
      expect(grpc_client).not_to have_received(:get_skill).with(
        hash_including(name: 'orbit', metadata_only: false)
      )
    end
  end
end
