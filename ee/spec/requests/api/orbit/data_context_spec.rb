# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Orbit::Data, '/orbit/context', :clean_gitlab_redis_rate_limiting,
  feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let(:token) { "MergeRequest[#{merge_request.id}]" }
  let_it_be(:group) { create(:group, :private, developers: [user]) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:author) { create(:user, name: 'Alex Author', username: 'alex_author') }
  let_it_be(:reviewer) { create(:user, name: 'Riley Reviewer', username: 'riley_reviewer') }
  let_it_be(:assignee) { create(:user, name: 'Sam Assignee', username: 'sam_assignee') }
  let_it_be(:milestone) { create(:milestone, project: project, title: 'Orbit milestone') }
  let_it_be(:head_pipeline) { create(:ci_pipeline, :running, project: project) }
  let_it_be(:merge_request) do
    create(:merge_request, head_pipeline: head_pipeline, source_project: project, target_project: project,
      author: author, title: 'Add entity context', source_branch: 'context-source', target_branch: 'master')
  end

  let_it_be(:issue) { create(:issue, project: project, author: author, milestone: milestone, title: 'Context issue') }
  let_it_be(:label) { create(:label, project: project, title: 'knowledge graph') }
  let_it_be(:other_project) { create(:project, :private) }
  let_it_be(:other_merge_request) do
    create(:merge_request, source_project: other_project, target_project: other_project)
  end

  let_it_be(:other_issue) { create(:issue, project: other_project) }
  let_it_be(:hidden_issue) { create(:issue, project: other_project, title: 'Hidden') }

  before_all do
    create(:merge_request_reviewer, merge_request: merge_request, reviewer: reviewer)
    create(:issue_assignee, issue: issue, assignee: assignee)
    create(:label_link, target: issue, label: label)
    create(:merge_request_issue, merge_request: merge_request, issue: issue)
    create(:merge_request_issue, merge_request: merge_request, issue: hidden_issue)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_feature_flags(orbit_promo_access_gate: false)
    allow(Analytics::KnowledgeGraph::JwtAuth).to receive(:generate_token).and_return('jwt')

    auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: true,
      admin_user?: false)
    allow(auth_context).to receive(:traversal_paths_in_scope) { |paths| paths }
    allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
  end

  def permissions_for(*permissions)
    permissions.map { |permission| Authz::PermissionGroups::Assignable.for_permission(permission).first.name }.uniq
  end

  def entity
    json_response['entities'].first
  end

  def send_request(user: self.user, params: {})
    post api('/orbit/context', user), params: { tokens: [token] }.merge(params), as: :json
  end

  it 'requires authentication' do
    send_request(user: nil)

    expect(response).to have_gitlab_http_status(:unauthorized)
  end

  it 'filters the tokens parameter from the request log' do
    expect(::API::API::LOGGER).to receive(:info).with(include(params: include('tokens' => '[FILTERED]')))

    send_request

    expect(response).to have_gitlab_http_status(:ok)
  end

  it 'requires the Orbit licensed feature' do
    stub_licensed_features(orbit: false)

    send_request

    expect(response).to have_gitlab_http_status(:forbidden)
  end

  it 'requires an enabled namespace' do
    auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: false)
    allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)

    send_request

    expect(response).to have_gitlab_http_status(:forbidden)
  end

  it 'counts against the orbit_query rate limit before the namespace check' do
    auth_context = instance_double(Analytics::KnowledgeGraph::AuthorizationContext, has_enabled_namespaces?: false)
    allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_return(auth_context)
    expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
      .with(:orbit_query, hash_including(scope: { user: user })).and_return(true)

    send_request

    expect(response).to have_gitlab_http_status(:too_many_requests)
  end

  it_behaves_like 'authorizing granular token permissions', :read_orbit do
    let(:boundary_object) { :user }
    let(:request) do
      post api('/orbit/context', personal_access_token: pat), params: { tokens: [token] }, as: :json
    end
  end

  describe 'validation' do
    [[], %w[a b], [1], [nil], [%w[a]], 'a'].each do |tokens|
      it "rejects tokens #{tokens.inspect}" do
        post api('/orbit/context', user), params: { tokens: tokens }, as: :json

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    it 'rejects a request body that is not JSON' do
      post api('/orbit/context', user), params: { tokens: [token] }

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'rejects a missing tokens parameter' do
      post api('/orbit/context', user), params: {}, as: :json

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    ['maybe', 'yes', 'true', 1, 0].each do |value|
      it "rejects the non-boolean expand #{value.inspect}" do
        send_request(params: { expand: value })

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    it 'rejects the gql response format' do
      send_request(params: { response_format: 'gql' })

      expect(response).to have_gitlab_http_status(:bad_request)
    end
  end

  describe 'merge request summary' do
    it 'returns the versioned envelope without an expansion', :aggregate_failures do
      send_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['version']).to eq(Analytics::Orbit::ContextService::VERSION)
      expect(entity).to include(
        'token' => token, 'resolved_token' => token, 'type' => 'MergeRequest', 'id' => merge_request.id.to_s,
        'found' => true, 'expansion' => nil
      )
      expect(entity['summary']).to include(
        'title' => 'Add entity context', 'iid' => merge_request.iid, 'namespace_path' => group.full_path,
        'project_path' => project.full_path, 'source_branch' => 'context-source', 'target_branch' => 'master',
        'head_pipeline_status' => 'running',
        'author' => hash_including('username' => 'alex_author'),
        'reviewers' => [hash_including('username' => 'riley_reviewer')]
      )
    end

    it 'lists readable linked issues only' do
      send_request

      expect(entity['summary']['linked_issues'])
        .to contain_exactly(hash_including('token' => "WorkItem[#{issue.id}]", 'title' => 'Context issue'))
    end

    it 'describes linked issues with type, string id and relation', :aggregate_failures do
      send_request

      expect(entity['summary']['linked_issues']).to contain_exactly(
        hash_including('type' => 'WorkItem', 'id' => issue.id.to_s, 'relation' => 'CLOSES', 'iid' => issue.iid)
      )
      expect(entity['summary']['truncated']).to eq([])
    end

    it 'names the lists that were cut', :aggregate_failures do
      stub_const('Analytics::Orbit::ContextService::MAX_USERS', 1)
      stub_const('Analytics::Orbit::ContextService::MAX_RELATED_ITEMS', 1)
      create(:merge_request_reviewer, merge_request: merge_request, reviewer: create(:user))
      create(:merge_request_issue, merge_request: merge_request, issue: create(:issue, project: project))

      send_request

      expect(entity['summary']['truncated']).to contain_exactly('reviewers', 'linked_issues')
      expect(entity['summary']['reviewers'].size).to eq(1)
      expect(entity['summary']['linked_issues'].size).to eq(1)
    end

    it 'drops unreadable users before the cut and lists the rest by id', :aggregate_failures do
      stub_const('Analytics::Orbit::ContextService::MAX_USERS', 2)
      blocked, second, third = create_list(:user, 3)
      [blocked, second, third].each do |user|
        create(:merge_request_reviewer, merge_request: merge_request, reviewer: user)
      end
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(anything, :read_user, blocked).and_return(false)

      send_request

      expect(entity['summary']['reviewers'].pluck('id')).to eq([reviewer.id, second.id])
      expect(entity['summary']['truncated']).to include('reviewers')
    end

    it 'reports the pipeline shown on the merge request page' do
      send_request

      expect(entity['summary']['head_pipeline_status']).to eq(merge_request.diff_head_pipeline.status)
    end

    it 'returns not_found without type or id for an unknown project path', :aggregate_failures do
      send_request(params: { tokens: ["gitlab-org-nope!1"] })

      expect(entity).to eq(
        'token' => 'gitlab-org-nope!1', 'type' => nil, 'id' => nil, 'found' => false,
        'error' => { 'code' => 'not_found' }, 'expansion' => nil
      )
    end
  end

  describe 'by role' do
    let_it_be(:guest) { create(:user, guest_of: project) }
    let_it_be(:reporter) { create(:user, reporter_of: project) }
    let_it_be(:confidential_issue_token) { create(:issue, :confidential, project: project) }

    it 'returns not_found for a guest on a merge request', :aggregate_failures do
      send_request(user: guest)

      expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })
    end

    it 'returns the merge request for a reporter' do
      send_request(user: reporter)

      expect(entity).to include('found' => true)
    end

    it 'returns not_found for a guest on a confidential issue used as the token', :aggregate_failures do
      send_request(user: guest, params: { tokens: ["WorkItem[#{confidential_issue_token.id}]"] })

      expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })
    end

    it 'returns a confidential issue used as the token for a reporter' do
      send_request(user: reporter, params: { tokens: ["WorkItem[#{confidential_issue_token.id}]"] })

      expect(entity).to include('found' => true)
    end
  end

  describe 'confidential linked work items' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:public_merge_request) { create(:merge_request, source_project: public_project) }
    let_it_be(:visible_issue) { create(:issue, project: public_project, title: 'Visible') }
    let_it_be(:confidential_issue) { create(:issue, :confidential, project: public_project, title: 'Secret') }

    let(:token) { "MergeRequest[#{public_merge_request.id}]" }

    before_all do
      create(:merge_request_issue, merge_request: public_merge_request, issue: visible_issue)
      create(:merge_request_issue, merge_request: public_merge_request, issue: confidential_issue)
    end

    def linked_titles
      entity['summary']['linked_issues'].pluck('title')
    end

    it 'omits the confidential issue for a session request' do
      send_request

      expect(linked_titles).to contain_exactly('Visible')
    end

    it 'still returns readable linked issues when unreadable ones sort first', :aggregate_failures do
      stub_const('Analytics::Orbit::ContextService::MAX_RELATED_ITEMS', 2)
      late_issue = create(:issue, project: public_project, title: 'Late')
      create(:merge_request_issue, merge_request: public_merge_request, issue: late_issue)

      send_request

      expect(linked_titles).to eq(%w[Visible Late])
    end

    it 'omits a linked merge request the user cannot read', :aggregate_failures do
      create(:merge_request_issue, merge_request: other_merge_request, issue: visible_issue)

      post api('/orbit/context', user), params: { tokens: ["WorkItem[#{visible_issue.id}]"] }, as: :json

      tokens = entity['summary']['linked_merge_requests'].pluck('token')
      expect(tokens).to contain_exactly("MergeRequest[#{public_merge_request.id}]")
    end

    it 'omits the confidential issue for a granular token that can read work items' do
      pat = create(:granular_pat, user: user, boundary: Authz::Boundary.for(:user),
        permissions: permissions_for(:read_orbit),
        additional_scopes: [{ boundary: Authz::Boundary.for(public_project),
                              permissions: permissions_for(:read_merge_request, :read_work_item) }])

      post api('/orbit/context', personal_access_token: pat), params: { tokens: [token] }, as: :json

      expect(linked_titles).to contain_exactly('Visible')
    end
  end

  describe 'work item summary' do
    let(:token) { "Issue[#{issue.id}]" }

    it 'reports the Issue alias as WorkItem', :aggregate_failures do
      send_request

      expect(entity).to include('resolved_token' => "WorkItem[#{issue.id}]", 'type' => 'WorkItem', 'found' => true)
      expect(entity['summary']).to include(
        'title' => 'Context issue', 'labels' => ['knowledge graph'],
        'assignees' => [hash_including('username' => 'sam_assignee')],
        'milestone' => { 'id' => milestone.id, 'title' => 'Orbit milestone' },
        'linked_merge_requests' => [hash_including('token' => "MergeRequest[#{merge_request.id}]")]
      )
    end

    context 'with a group-level work item' do
      let_it_be(:group_work_item) { create(:work_item, :epic, namespace: group) }

      before do
        stub_licensed_features(orbit: true, epics: true)
      end

      it 'resolves a group URL with a null project_path', :aggregate_failures do
        send_request(params: { tokens: [Gitlab::UrlBuilder.build(group_work_item)] })

        expect(entity).to include('found' => true, 'type' => 'WorkItem', 'id' => group_work_item.id.to_s)
        expect(entity['summary']).to include('namespace_path' => group.full_path, 'project_path' => nil)
      end

      it 'resolves path#iid for a group path' do
        send_request(params: { tokens: ["#{group.full_path}##{group_work_item.iid}"] })

        expect(entity).to include('found' => true, 'id' => group_work_item.id.to_s)
      end

      it 'returns not_found for a user who cannot read the group' do
        send_request(user: create(:user), params: { tokens: ["WorkItem[#{group_work_item.id}]"] })

        expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })
      end
    end
  end

  describe 'epic tokens' do
    let_it_be(:epic) { create(:epic, group: group) }
    let_it_be(:confidential_epic) { create(:epic, :confidential, group: group) }
    let_it_be(:guest) { create(:user, guest_of: group) }
    let_it_be(:group_issue) { create(:work_item, :issue, namespace: group) }
    let_it_be(:other_group) { create(:group, :private) }
    let(:work_item) { epic.work_item }

    before do
      stub_licensed_features(orbit: true, epics: true)
    end

    def epic_url(epic_group, iid)
      "#{Gitlab.config.gitlab.url}/groups/#{epic_group.full_path}/-/epics/#{iid}"
    end

    it 'resolves every epic form to the work item of the epic', :aggregate_failures do
      [
        "Epic[#{epic.id}]", "epic[#{epic.id}]", "gid://gitlab/Epic/#{epic.id}",
        epic_url(group, epic.iid), "#{epic_url(group, epic.iid)}/designs", "#{group.full_path}&#{epic.iid}"
      ].each do |text|
        send_request(params: { tokens: [text] })

        expect(entity).to include(
          'found' => true, 'type' => 'WorkItem', 'id' => work_item.id.to_s,
          'resolved_token' => "WorkItem[#{work_item.id}]"
        ), "expected #{text} to resolve"
        expect(entity['summary']).to include(
          'work_item_type' => 'epic', 'iid' => epic.iid, 'project_path' => nil, 'namespace_path' => group.full_path
        )
      end
    end

    it 'reports unsupported_type for other group-level types' do
      send_request(params: { tokens: ["#{Gitlab.config.gitlab.url}/groups/#{group.full_path}/-/boards/1"] })

      expect(entity).to include('found' => false, 'error' => { 'code' => 'unsupported_type' })
    end

    it 'returns invalid_token for a project-scoped epics URL' do
      send_request(params: { tokens: ["#{Gitlab.config.gitlab.url}/#{project.full_path}/-/epics/1"] })

      expect(entity).to include('found' => false, 'error' => { 'code' => 'invalid_token' })
    end

    it 'returns the identical not_found for unreadable, missing, wrong-group and non-epic work items',
      :aggregate_failures do
      send_request(params: { tokens: ["#{group.full_path}##{group_issue.iid}"] })
      expect(entity).to include('found' => true, 'id' => group_issue.id.to_s)

      other_epic = create(:epic, group: other_group)
      unfound = [
        "Epic[#{other_epic.id}]", "gid://gitlab/Epic/#{other_epic.id}", "Epic[#{non_existing_record_id}]",
        epic_url(other_group, other_epic.iid), epic_url(group, epic.iid + 1000), epic_url(group, other_epic.iid + 1000),
        "#{other_group.full_path}&#{other_epic.iid}", "#{group.full_path}&#{epic.iid + 1000}",
        "#{group.full_path}&#{group_issue.iid}", epic_url(group, group_issue.iid), "no/such-group&1",
        "#{project.full_path}&#{epic.iid}"
      ]

      unfound.each do |text|
        send_request(params: { tokens: [text] })

        # Type[id] and GID tokens only echo the id the caller sent.
        echoed_id = text[%r{\A(?:Epic\[|gid://gitlab/Epic/)(\d+)}, 1]
        expect(entity).to eq(
          'token' => text, 'type' => nil, 'id' => echoed_id, 'found' => false, 'error' => { 'code' => 'not_found' },
          'expansion' => nil
        ), "expected #{text} to be not_found"
      end
    end

    it 'does not resolve an epic without the epics license' do
      stub_licensed_features(orbit: true, epics: false)

      send_request(params: { tokens: ["Epic[#{epic.id}]"] })

      expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })
    end

    it 'hides a confidential epic from a guest but not from a developer', :aggregate_failures do
      send_request(user: guest, params: { tokens: ["Epic[#{confidential_epic.id}]"] })
      expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })

      send_request(params: { tokens: ["Epic[#{confidential_epic.id}]"] })
      expect(entity).to include('found' => true)
    end

    it 'checks the epic against the group boundary of a fine-grained token', :aggregate_failures do
      user_scope = { boundary: Authz::Boundary.for(:user), permissions: permissions_for(:read_orbit) }
      request = ->(*extra) do
        pat = create(:granular_pat, user: user, boundary: user_scope[:boundary],
          permissions: user_scope[:permissions], additional_scopes: extra)
        post api('/orbit/context', personal_access_token: pat), params: { tokens: ["Epic[#{epic.id}]"] }, as: :json
      end

      request.call
      expect(entity['found']).to be(false)

      request.call({ boundary: Authz::Boundary.for(group), permissions: permissions_for(:read_work_item) })
      expect(entity['found']).to be(true)
    end
  end

  describe 'job tokens' do
    let_it_be(:job) { create(:ci_build, :failed, pipeline: head_pipeline, project: project, name: 'rspec') }

    def granular_request(permission)
      pat = create(:granular_pat, user: user, boundary: Authz::Boundary.for(:user),
        permissions: permissions_for(:read_orbit),
        additional_scopes: [{ boundary: Authz::Boundary.for(project), permissions: permissions_for(permission) }])
      post api('/orbit/context', personal_access_token: pat), params: { tokens: ["Job[#{job.id}]"] }, as: :json
    end

    it 'resolves a job by id and by URL', :aggregate_failures do
      send_request(params: { tokens: ["Job[#{job.id}]"] })
      expect(entity).to include('found' => true, 'type' => 'Job', 'resolved_token' => "Job[#{job.id}]")

      send_request(params: { tokens: [Gitlab::UrlBuilder.build(job)] })
      expect(entity['found']).to be(true)
    end

    it 'needs read_job on a fine-grained token', :aggregate_failures do
      granular_request(:read_pipeline)
      expect(entity['found']).to be(false)

      granular_request(:read_job)
      expect(entity['found']).to be(true)
    end
  end

  describe 'token forms' do
    def resolved_id(token_text)
      send_request(params: { tokens: [token_text] })
      entity['id']
    end

    it 'resolves every supported form to the same merge request', :aggregate_failures do
      url = "#{Gitlab.config.gitlab.url}/#{project.full_path}/-/merge_requests/#{merge_request.iid}/diffs"

      expect(resolved_id("gid://gitlab/MergeRequest/#{merge_request.id}")).to eq(merge_request.id.to_s)
      expect(resolved_id(url)).to eq(merge_request.id.to_s)
      expect(resolved_id("#{project.full_path}!#{merge_request.iid}")).to eq(merge_request.id.to_s)
      expect(resolved_id("mergerequest[#{merge_request.id}]")).to eq(merge_request.id.to_s)
    end

    it 'resolves a work item URL and path#iid', :aggregate_failures do
      url = "#{Gitlab.config.gitlab.url}/#{project.full_path}/-/issues/#{issue.iid}"

      expect(resolved_id(url)).to eq(issue.id.to_s)
      expect(resolved_id("#{project.full_path}##{issue.iid}")).to eq(issue.id.to_s)
    end

    {
      'not a token' => 'invalid_token',
      'https://example.com/a/b/-/issues/1' => 'invalid_token',
      'Project[1]' => 'unsupported_type',
      'gid://gitlab/Project/1' => 'unsupported_type',
      'Issue[99999999999999999999]' => 'invalid_token'
    }.each do |text, code|
      it "returns #{code} for #{text}", :aggregate_failures do
        send_request(params: { tokens: [text] })

        expect(response).to have_gitlab_http_status(:ok)
        expect(entity).to include('found' => false, 'type' => nil, 'id' => nil, 'error' => { 'code' => code })
      end
    end

    it 'returns the identical not_found for unreadable, missing and wrong-kind records', :aggregate_failures do
      unfound = [
        "WorkItem[#{other_issue.id}]", "#{other_project.full_path}!#{other_merge_request.iid}",
        "#{project.full_path}##{issue.iid + 100}", 'no/such-project#1', "#{group.full_path}!1",
        "#{Gitlab.config.gitlab.url}/groups/#{project.full_path}/-/work_items/#{issue.iid}"
      ]

      bodies = unfound.map do |text|
        send_request(params: { tokens: [text] })
        entity.except('token', 'id')
      end

      expect(bodies.uniq).to eq(
        [{ 'type' => nil, 'found' => false, 'error' => { 'code' => 'not_found' }, 'expansion' => nil }]
      )
    end

    it 'echoes the sent id for an unfound Type[id] token and returns null for iid forms', :aggregate_failures do
      send_request(params: { tokens: ["WorkItem[#{other_issue.id}]"] })
      expect(entity['id']).to eq(other_issue.id.to_s)

      send_request(params: { tokens: ["#{other_project.full_path}##{other_issue.iid}"] })
      expect(entity['id']).to be_nil
    end
  end

  describe 'with a granular personal access token' do
    let(:user_scope) { { boundary: Authz::Boundary.for(:user), permissions: permissions_for(:read_orbit) } }

    def request_with(token_text, *extra_scopes)
      pat = create(:granular_pat, user: user, boundary: user_scope[:boundary], permissions: user_scope[:permissions],
        additional_scopes: extra_scopes)

      post api('/orbit/context', personal_access_token: pat), params: { tokens: [token_text] }, as: :json
    end

    it 'returns not_found for a project outside the token grants' do
      request_with(token)

      expect(entity).to include('found' => false, 'error' => { 'code' => 'not_found' })
    end

    it 'resolves the entity when the project boundary grants the permission' do
      request_with(token, { boundary: Authz::Boundary.for(project), permissions: permissions_for(:read_merge_request) })

      expect(entity).to include('found' => true)
    end

    it 'hides the head pipeline status without the read_pipeline permission', :aggregate_failures do
      request_with(token, { boundary: Authz::Boundary.for(project), permissions: permissions_for(:read_merge_request) })

      expect(entity['summary']).to include('head_pipeline_status' => nil)
    end

    it 'checks a group-level work item against its group boundary', :aggregate_failures do
      stub_licensed_features(orbit: true, epics: true)
      group_work_item = create(:work_item, :epic, namespace: group)

      request_with("WorkItem[#{group_work_item.id}]")
      expect(entity['found']).to be(false)

      request_with("WorkItem[#{group_work_item.id}]",
        { boundary: Authz::Boundary.for(group), permissions: permissions_for(:read_work_item) })
      expect(entity['found']).to be(true)
    end
  end

  describe 'expansion' do
    let(:graph) { { 'nodes' => [{ 'type' => 'MergeRequest', 'id' => merge_request.id.to_s }], 'edges' => [] } }
    let(:expansion_query) do
      {
        'name' => 'context_for_review',
        'parameters' => { 'node_ids' => [merge_request.id], 'limit' => Analytics::Orbit::ContextExpansionService::LIMIT }
      }
    end

    let(:outcome) { Analytics::KnowledgeGraph::QueryRunner::DataRenderer::Result.new(body: graph, error_code: nil) }

    def stub_runner(result)
      allow_next_instance_of(Analytics::KnowledgeGraph::QueryRunner) do |runner|
        allow(runner).to receive(:execute).and_return(result)
      end
    end

    context 'when the graph query runs' do
      before do
        stub_runner(outcome)
      end

      it 'runs the one named query with the merge request ID and a constant limit', :aggregate_failures do
        expect(Analytics::KnowledgeGraph::QueryRunner).to receive(:new) do |params, **_|
          expect(params['QueryType']).to eq('named')
          expect(Gitlab::Json::SafeParser.parse(params['Query'])).to eq(
            'name' => 'context_for_review',
            'parameters' => { 'node_ids' => [merge_request.id], 'limit' => Analytics::Orbit::ContextExpansionService::LIMIT }
          )
          instance_double(Analytics::KnowledgeGraph::QueryRunner, execute: outcome)
        end

        send_request(params: { expand: true })

        expect(entity['expansion']).to eq('result' => graph, 'query' => expansion_query)
      end

      it 'echoes a query that /orbit/query/:name sends to the graph unchanged', :aggregate_failures do
        sent = []
        allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:new) do |params, **_|
          sent << params
          result = sent.size == 1 ? outcome : Analytics::KnowledgeGraph::QueryRunner::Response.text('{}', status: 200)
          instance_double(Analytics::KnowledgeGraph::QueryRunner, execute: result)
        end

        send_request(params: { expand: true })
        post api('/orbit/query/context_for_review', user),
          params: { parameters: entity['expansion']['query']['parameters'] }, as: :json

        expect(response).to have_gitlab_http_status(:ok)
        expect(sent.size).to eq(2)
        expect(sent.map { |params| [params['QueryType'], params['Query']] }.uniq.size).to eq(1)
      end

      it 'returns outside_graph_scope without running a query when the record is outside the user scope',
        :aggregate_failures do
        allow(Analytics::KnowledgeGraph::AuthorizationContext.for(user))
          .to receive(:traversal_paths_in_scope).and_return([])
        expect(Analytics::KnowledgeGraph::QueryRunner).not_to receive(:new)

        send_request(params: { expand: true })

        expect(response).to have_gitlab_http_status(:ok)
        expect(entity['expansion']).to eq('error' => { 'code' => 'outside_graph_scope' }, 'query' => expansion_query)
      end

      it 'uses context_for_issue for a work item', :aggregate_failures do
        expect(Analytics::KnowledgeGraph::QueryRunner).to receive(:new) do |params, **_|
          expect(Gitlab::Json::SafeParser.parse(params['Query'])['name']).to eq('context_for_issue')
          instance_double(Analytics::KnowledgeGraph::QueryRunner, execute: outcome)
        end

        send_request(params: { expand: true, tokens: ["Issue[#{issue.id}]"] })

        expect(entity['expansion']['query']).to include(
          'name' => 'context_for_issue', 'parameters' => hash_including('node_ids' => [issue.id])
        )
      end

      context 'with an epic token' do
        let_it_be(:epic) { create(:epic, group: group) }
        let(:work_item) { epic.work_item }

        before do
          stub_licensed_features(orbit: true, epics: true)
        end

        it 'expands the epic work item', :aggregate_failures do
          expect(Analytics::KnowledgeGraph::QueryRunner).to receive(:new) do |params, **_|
            expect(Gitlab::Json::SafeParser.parse(params['Query'])).to include(
              'name' => 'context_for_issue', 'parameters' => hash_including('node_ids' => [work_item.id])
            )
            instance_double(Analytics::KnowledgeGraph::QueryRunner, execute: outcome)
          end

          send_request(params: { expand: true, tokens: ["Epic[#{epic.id}]"] })

          expect(entity).to include('type' => 'WorkItem', 'id' => work_item.id.to_s,
            'resolved_token' => "WorkItem[#{work_item.id}]")
          expect(entity['summary']).to include('work_item_type' => 'epic')
          expect(entity['expansion']['query']['parameters']['node_ids']).to eq([work_item.id])
        end
      end

      it 'does not run a query when expand is false' do
        expect(Analytics::KnowledgeGraph::QueryRunner).not_to receive(:new)

        send_request

        expect(entity['expansion']).to be_nil
      end

      it 'does not run a query for an unfound token', :aggregate_failures do
        expect(Analytics::KnowledgeGraph::QueryRunner).not_to receive(:new)

        send_request(params: { expand: true, tokens: ["WorkItem[#{other_issue.id}]"] })

        expect(entity['expansion']).to be_nil
      end

      %w[quota_exhausted timeout execution_error].each do |code|
        it "maps #{code} into the entity without failing the summary", :aggregate_failures do
          stub_runner(Analytics::KnowledgeGraph::QueryRunner::DataRenderer::Result.new(body: nil, error_code: code))

          send_request(params: { expand: true })

          expect(response).to have_gitlab_http_status(:ok)
          expect(entity['summary']['title']).to eq('Add entity context')
          expect(entity['expansion']).to eq('error' => { 'code' => code }, 'query' => expansion_query)
        end
      end

      it 'maps a missing governing namespace to billing_namespace_required' do
        allow(Analytics::KnowledgeGraph::GoverningNamespaceGuard).to receive(:ensure_selected!)
          .and_raise(Analytics::KnowledgeGraph::GoverningNamespaceGuard::RequiredError.new([group]))

        send_request(params: { expand: true })

        expect(entity['expansion']['error']).to include(
          'code' => 'billing_namespace_required', 'candidates' => [{ 'id' => group.id, 'name' => group.name }],
          'deep_link' => a_string_matching(%r{/-/profile/preferences})
        )
        expect(entity['expansion']['query']).to eq(expansion_query)
      end

      it 'maps a disconnected client to execution_error' do
        stub_runner(Analytics::KnowledgeGraph::QueryRunner::Response.text('', status: 499))

        send_request(params: { expand: true })

        expect(entity['expansion']).to eq('error' => { 'code' => 'execution_error' }, 'query' => expansion_query)
      end

      it 'passes the request context source type' do
        expect(Analytics::KnowledgeGraph::QueryRunner).to receive(:params_for)
          .with(hash_including(request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::REST)))
          .and_call_original

        send_request(params: { expand: true })
      end
    end
  end

  describe 'expansion scope with the real authorization context' do
    let_it_be(:root) { create(:group, :public) }
    let_it_be(:other_root) { create(:group, :public) }
    let_it_be(:scoped_project) { create(:project, :public, group: create(:group, :public, parent: root)) }
    let_it_be(:out_of_scope_project) { create(:project, :public, group: other_root) }
    let_it_be(:scoped_merge_request) do
      create(:merge_request, source_project: scoped_project, target_project: scoped_project)
    end

    let_it_be(:out_of_scope_merge_request) do
      create(:merge_request, source_project: out_of_scope_project, target_project: out_of_scope_project)
    end

    let_it_be(:scope_user) { create(:user, reporter_of: root, developer_of: other_root) }
    let(:graph) { { 'nodes' => [], 'edges' => [] } }
    let(:outcome) { Analytics::KnowledgeGraph::QueryRunner::DataRenderer::Result.new(body: graph, error_code: nil) }

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: root)
    end

    before do
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_call_original
      stub_feature_flags(orbit_promo_access_gate: false)
      allow_next_instance_of(Analytics::KnowledgeGraph::QueryRunner) do |runner|
        allow(runner).to receive(:execute).and_return(outcome)
      end
    end

    it 'runs the query for a record under an Orbit-enabled root where the user is a Reporter' do
      send_request(user: scope_user, params: { tokens: ["MergeRequest[#{scoped_merge_request.id}]"], expand: true })

      expect(entity['expansion']).to include('result' => graph,
        'query' => hash_including('name' => 'context_for_review'))
    end

    it 'returns outside_graph_scope for a record under a root without Orbit' do
      expect(Analytics::KnowledgeGraph::QueryRunner).not_to receive(:new)

      send_request(user: scope_user,
        params: { tokens: ["MergeRequest[#{out_of_scope_merge_request.id}]"], expand: true })

      expect(entity['expansion']).to include(
        'error' => { 'code' => 'outside_graph_scope' }, 'query' => hash_including('name' => 'context_for_review')
      )
    end
  end

  describe 'expansion scope for admins and auditors' do
    let_it_be(:enabled_root) { create(:group, :public) }
    let_it_be(:disabled_root) { create(:group, :public) }
    let_it_be(:enabled_project) { create(:project, :public, group: enabled_root) }
    let_it_be(:disabled_project) { create(:project, :public, group: disabled_root) }
    let_it_be(:enabled_merge_request) do
      create(:merge_request, source_project: enabled_project, target_project: enabled_project)
    end

    let_it_be(:disabled_merge_request) do
      create(:merge_request, source_project: disabled_project, target_project: disabled_project)
    end

    let(:graph) { { 'nodes' => [], 'edges' => [] } }
    let(:outcome) { Analytics::KnowledgeGraph::QueryRunner::DataRenderer::Result.new(body: graph, error_code: nil) }

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: enabled_root)
    end

    before do
      allow(Analytics::KnowledgeGraph::AuthorizationContext).to receive(:new).and_call_original
      stub_feature_flags(orbit_promo_access_gate: false)
      allow_next_instance_of(Analytics::KnowledgeGraph::QueryRunner) do |runner|
        allow(runner).to receive(:execute).and_return(outcome)
      end
    end

    {
      'an admin' => -> { create(:admin) },
      'an auditor' => -> { create(:auditor) }
    }.each do |label, build_user|
      context "for #{label}", :enable_admin_mode do
        let(:privileged_user) { instance_exec(&build_user) }

        it 'expands a record under an Orbit-enabled root' do
          send_request(user: privileged_user,
            params: { tokens: ["MergeRequest[#{enabled_merge_request.id}]"], expand: true })

          expect(entity['expansion']).to include('result' => graph)
        end

        it 'returns outside_graph_scope without running a query under a root without Orbit' do
          expect(Analytics::KnowledgeGraph::QueryRunner).not_to receive(:new)

          send_request(user: privileged_user,
            params: { tokens: ["MergeRequest[#{disabled_merge_request.id}]"], expand: true })

          expect(entity['expansion']).to include(
            'error' => { 'code' => 'outside_graph_scope' }, 'query' => hash_including('name' => 'context_for_review')
          )
        end
      end
    end
  end

  describe 'response_format llm' do
    it 'returns text/plain with the summary', :aggregate_failures do
      send_request(params: { response_format: 'llm' })

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.media_type).to eq('text/plain')
      version = Analytics::Orbit::ContextService::VERSION
      expect(response.body).to include("orbit_context version=#{version}", 'Add entity context', 'riley_reviewer')
    end

    it 'does not HTML-escape strings and sets the charset', :aggregate_failures do
      titled = create(:merge_request, source_project: project, title: 'Fix A & <b>')

      send_request(params: { response_format: 'llm', tokens: ["MergeRequest[#{titled.id}]"] })

      expect(response.body).to include('title="Fix A & <b>"')
      expect(response.media_type).to eq('text/plain')
      expect(response.headers['Content-Type']).to include('charset=utf-8')
    end

    it 'appends the graph section after the summary', :aggregate_failures do
      outcome = Analytics::KnowledgeGraph::QueryRunner::DataRenderer::Result.new(body: "nodes[1]:\n  a\n",
        error_code: nil)
      allow_next_instance_of(Analytics::KnowledgeGraph::QueryRunner) do |runner|
        allow(runner).to receive(:execute).and_return(outcome)
      end

      send_request(params: { response_format: 'llm', expand: true })

      expect(response.body).to end_with("graph:\nnodes[1]:\n  a\n")
    end
  end
end
