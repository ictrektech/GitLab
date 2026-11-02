# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::Data, :clean_gitlab_redis_rate_limiting, feature_category: :knowledge_graph do
  using RSpec::Parameterized::TableSyntax
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, owners: [user]) }
  let_it_be(:project) { create(:project, :private, namespace: group, maintainers: [user]) }
  let_it_be(:unauthorized_group) { create(:group, :private) }
  let_it_be(:user_namespace) { create(:namespace, owner: user) }

  let(:real_auth_context) { false }
  let(:enabled_root_namespace_ids) { [group.id] }
  let(:default_response) do
    {
      version: Analytics::Orbit::GrepService::VERSION,
      request: { search: 'search term', limit: 20, per_scope: 5 },
      target: { type: 'Project', id: project.id, token: "Project[#{project.id}]", full_path: project.full_path },
      scopes: [],
      results: [],
      result_count: 0,
      truncated: false
    }
  end

  before do
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })

    stub_auth_context(enabled_root_namespace_ids) unless real_auth_context
    stub_grep_response(default_response)
  end

  def stub_auth_context(root_ids)
    auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext,
      has_enabled_namespaces?: root_ids.any?, enabled_root_namespace?: false)
    allow(auth_context).to receive(:enabled_root_namespace?) { |root_id| root_ids.include?(root_id) }
    allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
  end

  def use_real_grep_service
    allow(Analytics::Orbit::GrepService).to receive(:new).and_call_original
    stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
  end

  def stub_grep_response(response)
    service = instance_double(Analytics::Orbit::GrepService, execute: response)
    allow(Analytics::Orbit::GrepService).to receive(:new).and_return(service)
  end

  def send_request(request_user: user, params: {})
    request_params = { search: 'search term', project_id: project.id }.merge(params).compact
    get api('/orbit/grep', request_user), params: request_params
  end

  it 'returns the versioned response' do
    send_request

    expect(response).to have_gitlab_http_status(:ok)
    expect(json_response).to include(
      'version' => Analytics::Orbit::GrepService::VERSION,
      'target' => { 'type' => 'Project', 'id' => project.id, 'token' => "Project[#{project.id}]",
                    'full_path' => project.full_path },
      'result_count' => 0,
      'truncated' => false
    )
  end

  where(:scopes_param) do
    [
      'projects,blobs',
      %w[projects blobs]
    ]
  end

  with_them do
    it 'accepts the requested scope list', :aggregate_failures do
      send_request(params: { scopes: scopes_param })

      expect(response).to have_gitlab_http_status(:ok)
      expect(Analytics::Orbit::GrepService).to have_received(:new).with(project,
        hash_including(scopes: %w[projects blobs]))
    end
  end

  it 'maps scope aliases to scope names' do
    send_request(params: { scopes: 'MR,Issue,comments,branch,merge_requests' })

    expect(Analytics::Orbit::GrepService).to have_received(:new).with(project,
      hash_including(scopes: %w[merge_requests work_items notes branches]))
  end

  it 'defaults to all scopes except branches when omitted', :aggregate_failures do
    send_request

    expect(Analytics::Orbit::GrepService).to have_received(:new).with(project,
      hash_including(scopes: Analytics::Orbit::GrepService::DEFAULT_SCOPES))
    expect(Analytics::Orbit::GrepService::DEFAULT_SCOPES).not_to include('branches')
  end

  it 'requires authentication' do
    send_request(request_user: nil)

    expect(response).to have_gitlab_http_status(:unauthorized)
  end

  it_behaves_like 'authorizing granular token permissions', [:read_orbit, :use_global_search] do
    let(:boundary_object) { :user }
    let(:request) do
      get api('/orbit/grep', personal_access_token: pat), params: {
        search: 'search term', project_id: project.id
      }
    end
  end

  it 'rejects a missing selector' do
    get api('/orbit/grep', user), params: { search: 'search term' }

    expect(response).to have_gitlab_http_status(:bad_request)
  end

  it 'rejects multiple selectors' do
    send_request(params: { namespace_id: group.id })

    expect(response).to have_gitlab_http_status(:bad_request)
  end

  it 'returns not found for a missing project' do
    send_request(params: { project_id: non_existing_record_id })

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'returns not found for an unauthorized namespace' do
    send_request(params: { project_id: nil, namespace_id: unauthorized_group.id })

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'resolves a target by full path' do
    send_request(params: { project_id: nil, full_path: project.full_path })

    expect(response).to have_gitlab_http_status(:ok)
  end

  it 'returns not found for a user namespace full path' do
    send_request(params: { project_id: nil, full_path: user_namespace.full_path })

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'requires an Orbit-enabled namespace' do
    stub_auth_context([])

    send_request

    expect(response).to have_gitlab_http_status(:forbidden)
  end

  context 'when the target is outside the user\'s Orbit-enabled root namespaces' do
    let(:enabled_root_namespace_ids) { [create(:group).id] }

    it 'returns not found for a project', :aggregate_failures do
      send_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(Analytics::Orbit::GrepService).not_to have_received(:new)
    end

    it 'returns not found for a group' do
      send_request(params: { project_id: nil, namespace_id: group.id })

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  it 'returns not found for a project in a subgroup of a disabled root group' do
    subgroup_project = create(:project, :private, namespace: create(:group, :private, parent: unauthorized_group),
      maintainers: [user])

    send_request(params: { project_id: subgroup_project.id })

    expect(response).to have_gitlab_http_status(:not_found)
  end

  it 'returns forbidden without the Orbit license' do
    stub_licensed_features(orbit: false)

    send_request

    expect(response).to have_gitlab_http_status(:forbidden)
  end

  it 'returns not found when the knowledge graph is not enabled' do
    stub_config(knowledge_graph: { 'enabled' => false })

    send_request

    expect(response).to have_gitlab_http_status(:not_found)
  end

  where(:params) do
    [
      { response_format: 'html' },
      { scopes: 'unknown' },
      { scopes: '' },
      { scopes: ',' },
      { limit: 0 },
      { limit: 51 },
      { per_scope: 0 },
      { per_scope: 11 },
      { limit: 2, per_scope: 3 },
      { search: 'a' },
      { search: ' ' },
      { search: 'a' * 257 }
    ]
  end

  with_them do
    it 'validates format, limits, and search' do
      send_request(params: params)

      expect(response).to have_gitlab_http_status(:bad_request)
    end
  end

  it 'accepts multi-byte search up to 256 bytes' do
    send_request(params: { search: 'é' * 128 })

    expect(response).to have_gitlab_http_status(:ok)
  end

  it 'rejects multi-byte search over 256 bytes with a consistent error' do
    send_request(params: { search: 'é' * 129 })

    expect(response).to have_gitlab_http_status(:bad_request)
    expect(json_response['message']).to eq('400 Bad request - search must contain between 2 and 256 bytes')
  end

  it 'strips padded search and passes limits to the service', :aggregate_failures do
    send_request(params: { search: '  padded term  ', limit: 7, per_scope: 3 })

    expect(Analytics::Orbit::GrepService).to have_received(:new).with(project,
      hash_including(search: 'padded term', limit: 7, per_scope: 3))
  end

  it 'returns compact plain text for the llm format', :aggregate_failures do
    grep = default_response.deep_dup
    grep[:result_count] = 1
    grep[:scopes] = [{
      name: 'merge_requests', status: 'ok', backend: 'basic', result_count: 1, pagination: { has_more: false }
    }]
    grep[:results] = [{
      scope: 'merge_requests', type: 'MergeRequest', id: 1, token: 'MergeRequest[1]', reference: { id: 1 },
      text: 'Add grep'
    }]
    stub_grep_response(grep)

    send_request(params: { response_format: 'llm' })

    expect(response).to have_gitlab_http_status(:ok)
    expect(response.media_type).to eq('text/plain')
    expect(response.headers['Content-Type']).to eq('text/plain; charset=utf-8')
    expect(response.body).to include("orbit_grep version=#{Analytics::Orbit::GrepService::VERSION} target=Project[")
    expect(response.body).to include('scopes="merge_requests"')
    expect(response.body).to include('- MergeRequest[1] type=MergeRequest text="Add grep"')
  end

  it 'exposes deterministic truncation metadata' do
    grep = default_response.merge(result_count: 1, truncated: true)
    stub_grep_response(grep)

    send_request(params: { limit: 1, per_scope: 1 })

    expect(json_response).to include('result_count' => 1, 'truncated' => true)
  end

  it_behaves_like 'rate limited endpoint', rate_limit_key: :orbit_query, use_second_scope: false do
    let(:current_user) { user }

    def request
      get api('/orbit/grep', current_user), params: { search: 'search term', project_id: project.id }
    end
  end

  it_behaves_like 'rate limited endpoint', rate_limit_key: :search_rate_limit, use_second_scope: false do
    let(:current_user) { user }

    def request
      get api('/orbit/grep', current_user), params: { search: 'search term', project_id: project.id }
    end
  end

  context 'with the real grep service' do
    before do
      use_real_grep_service
    end

    it 'lists every searched scope for a group in Basic search', :aggregate_failures do
      send_request(params: { project_id: nil, namespace_id: group.id })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['target']).to include('type' => 'Group', 'token' => "Group[#{group.id}]")
      scopes = json_response['scopes'].index_by { |scope| scope['name'] }
      expect(scopes.keys).to eq(Analytics::Orbit::GrepService::DEFAULT_SCOPES)
      expect(scopes.values_at('blobs', 'commits', 'notes')).to all(
        include('status' => 'unavailable', 'reason' => { 'code' => 'not_available_for_search_type' })
      )
      expect(scopes['work_items']).to include('status' => 'ok', 'backend' => 'basic')
    end

    it 'returns skipped scopes after the total limit is reached', :aggregate_failures do
      create_list(:work_item, 2, :issue, project: project, title: 'zebracorn grep needle')

      send_request(params: { search: 'zebracorn', limit: 1, per_scope: 1 })

      expect(json_response).to include('result_count' => 1, 'truncated' => true)
      expect(json_response['scopes'].first).to include('name' => 'work_items', 'status' => 'ok')
      expect(json_response['scopes'].drop(1)).to all(include('status' => 'skipped',
        'reason' => { 'code' => 'limit_reached' }))
    end

    it 'does not return confidential work items to a Guest', :aggregate_failures do
      guest = create(:user)
      project.add_guest(guest)
      public_issue = create(:issue, project: project, title: 'zebracorn public')
      create(:issue, :confidential, project: project, title: 'zebracorn confidential')

      send_request(request_user: guest, params: { search: 'zebracorn', scopes: 'work_items' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['results'].pluck('token')).to eq(["WorkItem[#{public_issue.id}]"])
    end

    it 'does not return confidential notes to a Guest', :aggregate_failures do
      guest = create(:user)
      project.add_guest(guest)
      issue = create(:issue, :confidential, project: project)
      create(:note_on_issue, noteable: issue, project: project, note: 'zebracorn secret note')

      send_request(request_user: guest, params: { search: 'zebracorn', scopes: 'notes' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['results']).to be_empty
    end

    it 'returns the state and project of a work item', :aggregate_failures do
      issue = create(:issue, :closed, project: project, title: 'zebracorn closed')

      send_request(params: { search: 'zebracorn', scopes: 'work_items' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['results'].sole).to include(
        'state' => 'closed',
        'reference' => { 'id' => issue.id, 'iid' => issue.iid, 'project_path' => project.full_path }
      )
    end

    it 'names the noteable of each note', :aggregate_failures do
      issue = create(:issue, project: project)
      merge_request = create(:merge_request, source_project: project, target_project: project)
      issue_note = create(:note_on_issue, noteable: issue, project: project, note: 'zebracorn on issue')
      merge_request_note = create(:note_on_merge_request, noteable: merge_request, project: project,
        note: 'zebracorn on merge request')

      send_request(params: { search: 'zebracorn', scopes: 'notes' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['results'].pluck('reference')).to contain_exactly(
        {
          'id' => issue_note.id, 'noteable' => "WorkItem[#{issue.id}]",
          'noteable_reference' => "#{project.full_path}##{issue.iid}"
        },
        {
          'id' => merge_request_note.id, 'noteable' => "MergeRequest[#{merge_request.id}]",
          'noteable_reference' => "#{project.full_path}!#{merge_request.iid}"
        }
      )
    end

    it 'isolates a backend error to one scope', :aggregate_failures do
      create(:issue, project: project, title: 'zebracorn survives')
      allow(SearchService).to receive(:new).and_wrap_original do |original, current_user, search_params|
        raise Gitlab::Git::CommandError, 'gitaly down' if search_params[:scope] == 'blobs'

        original.call(current_user, search_params)
      end

      send_request(params: { search: 'zebracorn', scopes: 'work_items,blobs' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['scopes']).to contain_exactly(
        include('name' => 'work_items', 'status' => 'ok'),
        { 'name' => 'blobs', 'status' => 'error', 'reason' => { 'code' => 'search_failed' } }
      )
      expect(json_response['result_count']).to eq(1)
    end

    it 'returns bad request once for an abusive search', :aggregate_failures do
      send_request(params: { search: 'the' })

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to include('stopword')
    end

    it 'returns bad request for a search shorter than two characters but two bytes long' do
      send_request(params: { search: '日' })

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'does not add queries for additional Basic commit results', :request_store, :use_sql_query_cache,
      :aggregate_failures do
      repo_project = create(:project, :private, :repository, namespace: group, maintainers: [user])
      allow(SearchService).to receive(:new).and_wrap_original do |original, current_user, search_params|
        if search_params[:scope] == 'commits'
          original.call(current_user, search_params)
        else
          instance_double(SearchService, scope: 'unavailable', abuse_detected?: false)
        end
      end

      control_params = { project_id: repo_project.id, search: 'test', limit: 10, per_scope: 1, scopes: 'commits' }
      multi_params = control_params.merge(per_scope: 5)
      send_request(params: control_params)
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { send_request(params: control_params) }
      control_results = json_response['results']
      multi = ActiveRecord::QueryRecorder.new(skip_cached: false) { send_request(params: multi_params) }
      multi_results = json_response['results']

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.dig('scopes', 0, 'backend')).to eq('basic')
      expect(control_results.size).to eq(1)
      expect(multi_results.size).to be > 1
      expect(multi.count).to be <= control.count
    end
  end

  context 'with the real authorization context' do
    let(:real_auth_context) { true }
    let_it_be(:root) { create(:group, :public) }
    let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: root) }
    let_it_be(:public_project) { create(:project, :public, namespace: create(:group, :public, parent: root)) }
    let_it_be(:issue) { create(:issue, project: public_project, title: 'zebracorn open') }

    before do
      use_real_grep_service
    end

    def grep_public_project(request_user)
      send_request(request_user: request_user, params: { search: 'zebracorn', project_id: public_project.id,
                                                         scopes: 'work_items' })
    end

    it 'allows a Reporter in the root group', :aggregate_failures do
      reporter = create(:user, reporter_of: root)

      grep_public_project(reporter)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['results'].pluck('token')).to eq(["WorkItem[#{issue.id}]"])
    end

    it 'allows a Reporter in a sibling subgroup to search a public project' do
      sibling = create(:group, :public, parent: root)
      reporter = create(:user, reporter_of: sibling)

      grep_public_project(reporter)

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'allows an administrator without memberships', :enable_admin_mode do
      grep_public_project(create(:admin))

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns forbidden on GitLab.com for an administrator without an entitled membership', :enable_admin_mode do
      stub_saas_features(gitlab_com_subscriptions: true)

      grep_public_project(create(:admin))

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to eq('403 Forbidden')
    end

    it 'returns not found for an administrator when the root is not enabled', :enable_admin_mode do
      enabled_namespace.destroy!

      grep_public_project(create(:admin))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns not found for a member of a disabled root group', :aggregate_failures do
      enabled_elsewhere = create(:group, :public)
      create(:knowledge_graph_enabled_namespace, namespace: enabled_elsewhere)
      disabled_root = create(:group, :public)
      disabled_project = create(:project, :public, namespace: disabled_root)
      member = create(:user, reporter_of: [enabled_elsewhere, disabled_root])

      send_request(request_user: member, params: { search: 'zebracorn', project_id: disabled_project.id })

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns forbidden for a user without a Reporter membership in an enabled root' do
      grep_public_project(create(:user, developer_of: public_project))

      expect(response).to have_gitlab_http_status(:forbidden)
    end
  end

  context 'with a granular token that only has read_orbit' do
    it 'returns forbidden', :aggregate_failures do
      token = create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user), permissions: %w[read_orbit])

      get api('/orbit/grep', personal_access_token: token), params: { search: 'search term', project_id: project.id }

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['error_description']).to include('Global Search: Use')
    end
  end
end
