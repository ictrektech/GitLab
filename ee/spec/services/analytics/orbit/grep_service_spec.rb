# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::GrepService, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, maintainers: [user]) }
  let(:target) { project }
  let(:limit) { 20 }
  let(:per_scope) { 5 }
  let(:scopes) { described_class::DEFAULT_SCOPES }
  let(:results) { {} }
  let(:unavailable_scopes) { [] }
  let(:failed_scopes) { [] }
  let(:abusive_scopes) { [] }
  let(:timed_out_scopes) { [] }
  let(:erroring_scopes) { [] }
  let(:search_type_error_scopes) { [] }
  let(:searches) { [] }
  let(:searched_scopes) { [] }
  let(:service_params) do
    { current_user: user, search: 'search term', limit: limit, per_scope: per_scope, scopes: scopes }
  end

  subject(:response) { described_class.new(target, **service_params).execute }

  def scope_for(name)
    response[:scopes].find { |scope| scope[:name] == name }
  end

  def results_for(name)
    response[:results].select { |result| result[:scope] == name }
  end

  before do
    allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(false)
    allow(SearchService).to receive(:new) do |_current_user, params|
      searches << params
      scope = params[:scope]
      instance_double(
        SearchService,
        scope: unavailable_scopes.include?(scope) ? 'work_items' : scope,
        search_type: scope == 'blobs' ? 'zoekt' : 'advanced',
        search_type_errors: search_type_error_scopes.include?(scope) ? 'too many projects' : nil,
        abuse_detected?: abusive_scopes.include?(scope),
        abuse_messages: ['Query string abusive tiny search detected'],
        search_results: instance_double(Gitlab::SearchResults, failed?: failed_scopes.include?(scope))
      ).tap do |search|
        allow(search).to receive(:search_objects).with(anything) do
          searched_scopes << scope
          raise ActiveRecord::QueryCanceled if timed_out_scopes.include?(scope)
          raise Gitlab::Git::CommandError, 'boom' if erroring_scopes.include?(scope)

          results.fetch(scope, [])
        end
      end
    end
  end

  it 'uses one tier-selected search per scope in fixed order', :aggregate_failures do
    expect(response).to include(
      version: described_class::VERSION,
      request: { search: 'search term', limit: 20, per_scope: 5 },
      target: { type: 'Project', id: project.id, token: "Project[#{project.id}]", full_path: project.full_path },
      results: [],
      result_count: 0,
      truncated: false
    )
    expect(response[:scopes].pluck(:name)).to eq(described_class::DEFAULT_SCOPES)
    expect(response[:scopes]).to all(include(status: 'ok', result_count: 0, pagination: { has_more: false }))
    # The search is asked for one extra row so truncation never needs a COUNT query.
    expect(searches.drop(1).pluck(:scope)).to eq(described_class::DEFAULT_SCOPES)
    expect(searches.drop(1)).to all(include(project_id: project.id, search: 'search term', per_page: 6))
    expect(searches).to all(not_include(:search_type))
  end

  it 'reports a group target' do
    group = create(:group)

    result = described_class.new(group, **service_params).execute

    expect(result[:target]).to eq(type: 'Group', id: group.id, token: "Group[#{group.id}]", full_path: group.full_path)
  end

  context 'when no known scopes are requested' do
    let(:scopes) { %w[unknown] }

    it 'builds no search and returns no scopes', :aggregate_failures do
      expect(response).to include(scopes: [], results: [], result_count: 0, truncated: false)
      expect(searches).to be_empty
    end
  end

  context 'when selecting a subset of scopes' do
    let(:scopes) { %w[projects blobs] }

    it 'searches only the selected scopes in canonical order', :aggregate_failures do
      expect(response[:scopes].pluck(:name)).to eq(%w[blobs projects])
      expect(searches.drop(1).pluck(:scope)).to eq(%w[blobs projects])
    end

    it 'spends the total budget only on selected scopes', :aggregate_failures do
      results['blobs'] = [instance_double(Gitlab::Search::FoundBlob, project_id: project.id,
        project: project, ref: 'master', path: 'README.md', startline: nil)]
      results['projects'] = [project]

      result = described_class.new(target, **service_params, limit: 2, per_scope: 1).execute

      expect(result).to include(result_count: 2, truncated: false)
      expect(result[:scopes].pluck(:name)).to eq(%w[blobs projects])
    end

    it 'reports an unavailable selected scope', :aggregate_failures do
      unavailable_scopes << 'blobs'

      expect(response[:scopes]).to include(
        { name: 'blobs', status: 'unavailable', reason: { code: 'not_available_for_search_type' } }
      )
      expect(response[:scopes].pluck(:name)).to eq(%w[blobs projects])
    end
  end

  it 'reports failed searches without hiding results from other scopes' do
    failed_scopes << 'blobs'
    results['work_items'] = [build_stubbed(:work_item)]

    expect(scope_for('blobs')).to eq({ name: 'blobs', status: 'error', reason: { code: 'search_failed' } })
    expect(response[:result_count]).to eq(1)
  end

  it 'reports a timed out scope while retaining partial results' do
    timed_out_scopes << 'blobs'
    results['work_items'] = [build_stubbed(:work_item)]

    expect(scope_for('blobs')).to eq({ name: 'blobs', status: 'error', reason: { code: 'timeout' } })
    expect(response[:result_count]).to eq(1)
  end

  it 'isolates a backend error to its scope and tracks it', :aggregate_failures do
    erroring_scopes << 'blobs'
    results['work_items'] = [build_stubbed(:work_item)]

    expect(Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(Gitlab::Git::CommandError),
      scope: 'blobs')
    expect(scope_for('blobs')).to eq({ name: 'blobs', status: 'error', reason: { code: 'search_failed' } })
    expect(scope_for('merge_requests')).to include(status: 'ok')
    expect(response[:result_count]).to eq(1)
  end

  it 'tracks a backend outage once per request', :aggregate_failures do
    erroring_scopes.push('work_items', 'blobs')

    expect(Gitlab::ErrorTracking).to receive(:track_exception)
      .with(instance_of(Gitlab::Git::CommandError), scope: 'work_items').once
    expect(scope_for('work_items')).to include(status: 'error')
    expect(scope_for('blobs')).to include(status: 'error')
  end

  it 'reports a scope with a search type error as unavailable', :aggregate_failures do
    search_type_error_scopes << 'blobs'

    expect(scope_for('blobs'))
      .to eq({ name: 'blobs', status: 'unavailable', reason: { code: 'search_type_error' } })
    expect(scope_for('commits')).to include(status: 'ok')
  end

  context 'with the search rate limit' do
    it 'charges one unit for each search after the first', :aggregate_failures do
      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(:search_rate_limit, hash_including(scope: { user: user })).exactly(scopes.size - 1).times
        .and_return(false)

      expect(response[:scopes]).to all(include(status: 'ok'))
    end

    it 'does not charge a scope that never runs a search', :aggregate_failures do
      unavailable_scopes << 'merge_requests'
      search_type_error_scopes << 'notes'
      abusive_scopes << 'blobs'

      expect(Gitlab::ApplicationRateLimiter).to receive(:throttled?).exactly(scopes.size - 4).times.and_return(false)
      expect(scope_for('merge_requests')).to include(status: 'unavailable')
    end

    it 'reports the remaining scopes as rate_limited once throttled', :aggregate_failures do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(false, true)

      expect(response[:scopes].pluck(:status)).to eq(%w[ok ok] + (%w[error] * (scopes.size - 2)))
      expect(response[:scopes].last).to eq({ name: scopes.last, status: 'error', reason: { code: 'rate_limited' } })
      expect(Gitlab::ApplicationRateLimiter).to have_received(:throttled?).twice
      expect(searched_scopes).to eq(scopes.first(2))
      expect(searches.size).to eq(4)
    end
  end

  it 'reports a scope whose search is abusive as invalid_search while the first scope is accepted' do
    abusive_scopes << 'merge_requests'
    results['work_items'] = [build_stubbed(:work_item)]

    expect(scope_for('merge_requests')).to eq(
      { name: 'merge_requests', status: 'error', reason: { code: 'invalid_search' } }
    )
    expect(scope_for('work_items')).to include(status: 'ok', result_count: 1)
  end

  it 'raises once for an abusive search before searching any scope', :aggregate_failures do
    abusive_scopes << 'work_items'

    expect { response }.to raise_error(described_class::AbusiveSearchError, /abusive tiny search/)
    expect(searches.size).to eq(1)
  end

  context 'with blob results' do
    let(:scopes) { %w[blobs] }
    let(:commit_sha) { '0123456789abcdef0123456789abcdef01234567' }

    def stub_blob_search(search_type, blobs)
      allow(SearchService).to receive(:new).with(user, hash_including(scope: 'blobs')).and_return(
        instance_double(SearchService, scope: 'blobs', search_type: search_type,
          search_type_errors: nil, abuse_detected?: false,
          search_results: instance_double(Gitlab::SearchResults, failed?: false),
          search_objects: blobs)
      )
    end

    def blob(path:, ref: 'main', startline: nil, data: nil)
      instance_double(Gitlab::Search::FoundBlob, project_id: project.id, project: project,
        ref: ref, path: path, startline: startline, data: data)
    end

    before do
      allow(project).to receive(:default_branch).and_return('main')
    end

    it 'uses the default branch and indexed commit for Advanced Search results' do
      stub_blob_search('advanced', [blob(path: 'README.md', ref: commit_sha)])

      expect(response[:results].first).to include(
        type: 'File', id: nil, token: nil, text: 'README.md',
        reference: {
          project_id: project.id, project_path: project.full_path, path: 'README.md', branch: 'main',
          commit_sha: commit_sha
        }
      )
    end

    it 'keeps the branch name from Basic search results and has no commit SHA' do
      stub_blob_search('basic', [blob(path: 'README.md', ref: 'feature')])

      expect(response[:results].first[:reference]).to eq(project_id: project.id, project_path: project.full_path,
        path: 'README.md', branch: 'feature', commit_sha: nil)
    end

    it 'dedupes Basic search rows for the same file and keeps the first matched line', :aggregate_failures do
      stub_blob_search('basic', [
        blob(path: 'README.md', startline: 3, data: "a zebracorn\nb"),
        blob(path: 'README.md', startline: 9, data: 'zebracorn again'),
        blob(path: 'docs/zebracorn.md', startline: 1, data: 'zebracorn')
      ])

      expect(response[:results].pluck(:text)).to eq(%w[README.md docs/zebracorn.md])
      expect(response[:results].first[:matches]).to eq([{ start_line: 3, end_line: 4, text: "a zebracorn\nb" }])
      expect(scope_for('blobs')).to include(result_count: 2, pagination: { has_more: false })
    end

    it 'finds later distinct Basic files past many duplicate rows and fetches a wider window', :aggregate_failures do
      rows = Array.new(8) { |i| blob(path: 'README.md', startline: i + 1) } + [blob(path: 'docs/zebracorn.md')]
      stub_blob_search('basic', rows)

      result = described_class.new(target, **service_params, limit: 3, per_scope: 2).execute

      expect(result[:results].pluck(:text)).to eq(%w[README.md docs/zebracorn.md])
      expect(result[:scopes].first).to include(result_count: 2, pagination: { has_more: false })
      expect(SearchService).to have_received(:new)
        .with(user, hash_including(scope: 'blobs', per_page: described_class::BASIC_BLOB_WINDOW))
    end

    it 'does not report more results when the extra Basic row is another match in the last file' do
      stub_blob_search('basic', Array.new(4) { |i| blob(path: 'README.md', startline: i + 1) })

      expect(scope_for('blobs')).to include(result_count: 1, pagination: { has_more: false })
    end

    it 'reports more results when the Basic window is full' do
      stub_blob_search('basic', Array.new(described_class::BASIC_BLOB_WINDOW) do |i|
        blob(path: 'README.md', startline: i)
      end)

      expect(scope_for('blobs')).to include(result_count: 1, pagination: { has_more: true })
    end

    it 'reports more results when there are more distinct Basic files than requested' do
      stub_blob_search('basic', Array.new(3) { |i| blob(path: "file#{i}.md") })

      expect(described_class.new(target, **service_params, per_scope: 2).execute[:scopes].first)
        .to include(result_count: 2, pagination: { has_more: true })
    end

    it 'uses the default branch for a Zoekt blob' do
      zoekt_blob = instance_double(Search::FoundMultiLineBlob, project: project, path: 'README.md')
      stub_blob_search('zoekt', [zoekt_blob])

      expect(response[:results].first[:reference]).to eq(project_id: project.id, project_path: project.full_path,
        path: 'README.md', branch: 'main', commit_sha: nil)
      expect(response[:results].first).not_to have_key(:matches)
    end
  end

  it 'reports truncation for real Basic search without_count results' do
    stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
    create_list(:issue, 2, project: project, title: 'Orbit truncation needle')
    allow(SearchService).to receive(:new).and_call_original

    result = described_class.new(project, current_user: user, search: 'Orbit truncation needle', limit: 5,
      per_scope: 1, scopes: %w[work_items]).execute

    expect(result).to include(result_count: 1, truncated: true)
    expect(result[:scopes]).to contain_exactly(include(name: 'work_items', pagination: { has_more: true }))
  end

  it 'searches real work items using Basic search' do
    stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
    issue = create(:issue, project: project, title: 'Orbit needle for grep')
    allow(SearchService).to receive(:new).and_call_original

    result = described_class.new(project, current_user: user, search: 'Orbit needle', limit: 5,
      per_scope: 5, scopes: %w[work_items]).execute

    expect(result[:scopes]).to contain_exactly(include(name: 'work_items', status: 'ok', backend: 'basic'))
    expect(result[:results]).to contain_exactly(
      include(scope: 'work_items', type: 'WorkItem', id: issue.id, token: "WorkItem[#{issue.id}]"))
  end

  context 'with real Basic search for notes and users' do
    before do
      stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
      allow(SearchService).to receive(:new).and_call_original
    end

    it 'reports truncation for notes without running a COUNT query', :aggregate_failures do
      issue = create(:issue, project: project)
      create_list(:note_on_issue, 3, noteable: issue, project: project, note: 'Orbit note needle')

      queries = ActiveRecord::QueryRecorder.new do
        result = described_class.new(project, current_user: user, search: 'Orbit note needle', limit: 5,
          per_scope: 1, scopes: %w[notes]).execute

        expect(result).to include(result_count: 1, truncated: true)
      end

      expect(queries.occurrences.keys.grep(/COUNT\(\*\)/)).to be_empty
    end

    it 'does not load the noteable once per note', :aggregate_failures do
      issue = create(:issue, project: project)
      create(:note_on_issue, noteable: issue, project: project, note: 'Orbit note needle')
      grep = -> {
        described_class.new(project, current_user: user, search: 'Orbit note needle', limit: 20,
          per_scope: 10, scopes: %w[notes]).execute
      }

      control = ActiveRecord::QueryRecorder.new { grep.call }
      create_list(:note_on_issue, 3, noteable: issue, project: project, note: 'Orbit note needle')

      result = nil
      expect { result = grep.call }.not_to exceed_query_limit(control)
      expect(result[:results].pluck(:reference).pluck(:noteable_reference).uniq)
        .to eq(["#{project.full_path}##{issue.iid}"])
    end

    it 'reports truncation for users without running a COUNT query', :aggregate_failures do
      create_list(:user, 2, developer_of: project).each_with_index { |u, i| u.update!(name: "Orbitneedle #{i}") }

      queries = ActiveRecord::QueryRecorder.new do
        result = described_class.new(project, current_user: user, search: 'Orbitneedle', limit: 5,
          per_scope: 1, scopes: %w[users]).execute

        expect(result).to include(result_count: 1, truncated: true)
      end

      expect(queries.occurrences.keys.grep(/COUNT\(\*\)/)).to be_empty
    end
  end

  it 'returns several distinct files from real Basic blob search with repeated matches', :aggregate_failures do
    repository_project = create(:project, :public, :repository, maintainers: [user])
    stub_ee_application_setting(elasticsearch_search: false, elasticsearch_indexing: false)
    allow(SearchService).to receive(:new).and_call_original

    result = described_class.new(repository_project, current_user: user, search: 'def', limit: 10,
      per_scope: 5, scopes: %w[blobs]).execute

    paths = result[:results].pluck(:reference).pluck(:path)
    expect(paths.size).to be > 1
    expect(paths).to eq(paths.uniq)
  end

  it 'maps database and source-code results to graph references', :aggregate_failures do
    allow(project).to receive(:default_branch).and_return('main')
    work_item = build_stubbed(:work_item, title: 'Find graph entities')
    merge_request = build_stubbed(:merge_request, title: 'Add grep')
    blob = instance_double(
      Gitlab::Search::FoundBlob,
      project_id: project.id,
      project: project,
      ref: 'master',
      path: 'ee/lib/api/orbit/data.rb',
      startline: nil
    )
    commit = instance_double(Commit, id: 'abc123', project: project, title: "Fix\nsearch")
    note = build_stubbed(:note, note: "First\nsecond")
    results.merge!(
      'work_items' => [work_item],
      'merge_requests' => [merge_request],
      'blobs' => [blob],
      'commits' => [commit],
      'notes' => [note]
    )

    expect(response[:results].first(5)).to eq([
      {
        scope: 'work_items', type: 'WorkItem', id: work_item.id, token: "WorkItem[#{work_item.id}]",
        reference: { id: work_item.id, iid: work_item.iid, project_path: work_item.project.full_path },
        text: 'Find graph entities', state: work_item.state
      },
      {
        scope: 'merge_requests', type: 'MergeRequest', id: merge_request.id,
        token: "MergeRequest[#{merge_request.id}]",
        reference: { id: merge_request.id, iid: merge_request.iid, project_path: merge_request.project.full_path },
        text: 'Add grep', state: merge_request.state
      },
      {
        scope: 'blobs', type: 'File', id: nil, token: nil,
        reference: {
          project_id: project.id, project_path: project.full_path, path: 'ee/lib/api/orbit/data.rb',
          branch: 'main', commit_sha: nil
        },
        text: 'ee/lib/api/orbit/data.rb'
      },
      {
        scope: 'commits', type: 'Commit', id: 'abc123', token: "#{project.full_path}@abc123",
        reference: { project_id: project.id, project_path: project.full_path, sha: 'abc123' }, text: 'Fix search'
      },
      {
        scope: 'notes', type: 'Note', id: note.id, token: "Note[#{note.id}]",
        reference: {
          id: note.id, noteable: "WorkItem[#{note.noteable_id}]",
          noteable_reference: "#{note.project.full_path}##{note.noteable.iid}"
        },
        text: 'First second'
      }
    ])
  end

  it 'names the merge request or commit a note belongs to', :aggregate_failures do
    merge_request = build_stubbed(:merge_request, source_project: project, target_project: project)
    on_merge_request = build_stubbed(:note, project: project, noteable: merge_request)
    commit_sha = '0123456789abcdef0123456789abcdef01234567'
    on_commit = build_stubbed(:note_on_commit, project: project, commit_id: commit_sha)
    results['notes'] = [on_merge_request, on_commit]
    allow(on_commit).to receive(:noteable).and_call_original

    expect(results_for('notes').pluck(:reference)).to eq([
      {
        id: on_merge_request.id, noteable: "MergeRequest[#{merge_request.id}]",
        noteable_reference: "#{project.full_path}!#{merge_request.iid}"
      },
      { id: on_commit.id, noteable_reference: "#{project.full_path}@#{commit_sha}" }
    ])
    expect(on_commit).not_to have_received(:noteable)
  end

  it 'names the namespace of a note on a group-level work item' do
    group = build_stubbed(:group)
    work_item = build_stubbed(:work_item, :group_level, namespace: group)
    results['notes'] = [build_stubbed(:note, project: nil, noteable: work_item)]

    expect(results_for('notes').first[:reference]).to include(
      noteable: "WorkItem[#{work_item.id}]", noteable_reference: "#{group.full_path}##{work_item.iid}"
    )
  end

  it 'omits the noteable reference when the noteable is missing' do
    note = build_stubbed(:note_on_issue, project: project)
    allow(note).to receive(:noteable).and_return(nil)
    results['notes'] = [note]

    expect(results_for('notes').first[:reference]).to eq(id: note.id, noteable: "WorkItem[#{note.noteable_id}]")
  end

  it 'keeps only the id for notes on other noteables', :aggregate_failures do
    on_snippet = build_stubbed(:note_on_project_snippet, project: project)
    on_design = build_stubbed(:note_on_design, project: project)
    results['notes'] = [on_snippet, on_design]

    expect(results_for('notes').pluck(:reference)).to eq([{ id: on_snippet.id }, { id: on_design.id }])
  end

  it 'names the namespace of a group-level work item' do
    group = build_stubbed(:group)
    work_item = build_stubbed(:work_item, :group_level, namespace: group)
    results['work_items'] = [work_item]

    expect(results_for('work_items').first[:reference])
      .to eq(id: work_item.id, iid: work_item.iid, namespace_path: group.full_path)
  end

  it 'returns the state of a milestone' do
    results['milestones'] = [build_stubbed(:milestone, project: project, state: 'closed')]

    expect(results_for('milestones').first).to include(reference: { id: anything }, state: 'closed')
  end

  it 'includes a user text in search results' do
    results['users'] = [user]

    expect(results_for('users').first).to include(
      type: 'User', token: "User[#{user.id}]", reference: { id: user.id }, text: "#{user.username} #{user.name}"
    )
  end

  it 'limits long text for compact responses' do
    results['notes'] = [build_stubbed(:note, note: 'a' * 300)]

    expect(results_for('notes').first[:text]).to eq("#{'a' * 197}...")
  end

  it 'marks a scope with more rows than requested as truncated', :aggregate_failures do
    results['work_items'] = build_stubbed_list(:work_item, 6)

    expect(response).to include(result_count: 5, truncated: true)
    expect(scope_for('work_items')).to include(result_count: 5, pagination: { has_more: true })
  end

  it 'reports scopes unavailable for the selected level and tier' do
    unavailable_scopes.concat(%w[blobs commits notes])

    expect(response[:scopes].select { |scope| scope[:status] == 'unavailable' }).to eq(
      %w[blobs commits notes].map do |name|
        { name: name, status: 'unavailable', reason: { code: 'not_available_for_search_type' } }
      end
    )
  end

  it 'truncates deterministically by scope order and total limit' do
    work_items = build_stubbed_list(:work_item, 2)
    results['work_items'] = work_items

    result = described_class.new(target, **service_params, limit: 1, per_scope: 1, scopes: %w[work_items]).execute

    expect(result).to include(result_count: 1, truncated: true)
    expect(result[:results].pluck(:token)).to eq(["WorkItem[#{work_items.first.id}]"])
  end

  it 'clamps later scopes to the remaining total budget', :aggregate_failures do
    results['work_items'] = build_stubbed_list(:work_item, 2)

    described_class.new(target, **service_params, limit: 3, per_scope: 2, scopes: %w[work_items merge_requests]).execute

    expect(searches.drop(1).pluck(:scope, :per_page)).to eq([['work_items', 3], ['merge_requests', 2]])
  end

  it 'skips the remaining scopes and reports truncation when the total limit is reached', :aggregate_failures do
    results['work_items'] = [build_stubbed(:work_item)]

    result = described_class.new(target, **service_params, limit: 1, per_scope: 1).execute

    expect(result).to include(result_count: 1, truncated: true)
    expect(result[:scopes].first).to include(name: 'work_items', status: 'ok')
    expect(result[:scopes].drop(1)).to all(include(status: 'skipped', reason: { code: 'limit_reached' }))
    expect(result[:scopes].pluck(:name)).to eq(described_class::DEFAULT_SCOPES)
    expect(searches.drop(1).pluck(:scope)).to eq(['work_items'])
  end

  describe '.normalize_scopes' do
    it 'maps aliases in any case to scope names and keeps unknown names for validation' do
      expect(described_class.normalize_scopes(%w[MR issue Comments branch merge_requests unknown]))
        .to eq(%w[merge_requests work_items notes branches unknown])
    end

    it 'maps node type names to scope names' do
      expect(described_class.normalize_scopes(%w[MergeRequest WorkItem File Branch Note]))
        .to eq(%w[merge_requests work_items blobs branches notes])
    end
  end

  context 'with the branches scope' do
    let_it_be(:repo_project) { create(:project, :repository, :private, maintainers: [user]) }

    let(:target) { repo_project }
    let(:scopes) { %w[work_items branches] }
    let(:service_params) do
      { current_user: user, search: 'awesome', limit: limit, per_scope: per_scope, scopes: scopes }
    end

    def granular_pat(*names)
      permissions = names.map { |name| Authz::PermissionGroups::Assignable.for_permission(name).first.name }
      create(:granular_pat, user: user, boundary: Authz::Boundary.for(repo_project), permissions: permissions)
    end

    it 'returns matching branch names as branch tokens', :aggregate_failures do
      expect(scope_for('branches')).to include(status: 'ok', backend: 'basic')
      expect(results_for('branches')).to include(
        scope: 'branches', type: 'Branch', id: nil, token: "#{repo_project.full_path}@improve/awesome",
        text: 'improve/awesome',
        reference: { project_id: repo_project.id, project_path: repo_project.full_path, name: 'improve/awesome' }
      )
      expect(searches.pluck(:scope)).not_to include('branches')
    end

    it 'matches names case-insensitively, with words in order and glob characters escaped', :aggregate_failures do
      result = ->(search) { described_class.new(target, **service_params, search: search).execute }

      expect(result.call('IMPROVE awesome')[:results].pluck(:text)).to include('improve/awesome')
      expect(result.call('impr*ve')[:results].pluck(:text)).not_to include('improve/awesome')
    end

    it 'keeps characters that are neither letters nor glob characters' do
      result = described_class.new(target, **service_params, search: 'e/aw').execute

      expect(result[:results].pluck(:text)).to include('improve/awesome')
    end

    it 'reads branch names from the cache, not the branch list' do
      expect(BranchesFinder).not_to receive(:new)

      expect(scope_for('branches')).to include(status: 'ok')
    end

    it 'charges the search rate limit for the branch search' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_return(true)

      expect(scope_for('branches')).to include(status: 'error', reason: { code: 'rate_limited' })
    end

    it 'is unavailable for a group target' do
      result = described_class.new(create(:group), **service_params).execute

      expect(result[:scopes].find { |scope| scope[:name] == 'branches' })
        .to include(status: 'unavailable', reason: { code: 'not_available_for_target' })
    end

    it 'is unavailable in a project whose code is for members only', :aggregate_failures do
      members_only = create(:project, :repository, :public, repository_access_level: ProjectFeature::PRIVATE)
      expect(Repositories::BranchNamesFinder).not_to receive(:new)

      result = described_class.new(members_only, **service_params).execute

      expect(result[:scopes].find { |scope| scope[:name] == 'branches' })
        .to include(status: 'unavailable', reason: { code: 'not_available_for_target' })
    end

    context 'with a fine-grained token' do
      let(:service_params) { super().merge(access_token: granular_pat(*grants)) }

      context 'without read_branch' do
        let(:grants) { %i[read_code] }

        it 'is unavailable and does not list branches' do
          expect(Repositories::BranchNamesFinder).not_to receive(:new)

          expect(scope_for('branches')).to include(status: 'unavailable', reason: { code: 'not_available_for_target' })
        end
      end

      context 'with read_branch' do
        let(:grants) { %i[read_branch] }

        it 'lists branches' do
          expect(scope_for('branches')).to include(status: 'ok')
        end
      end
    end
  end
end
