# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReconcileWorkItemsService, feature_category: :importers do
  using RSpec::Parameterized::TableSyntax

  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      authority_state: authority_state,
      application_generation: application_generation,
      provider_full_name: 'example/connected'
    )
  end

  let!(:work_items_state) do
    create(
      :import_sync_repository_state,
      repository: repository,
      domain: :work_items,
      desired_generation: 2,
      synced_generation: 1,
      last_successful_sync_at: last_successful_sync_at
    )
  end

  let(:authority_state) { :provider_canonical }
  let(:application_generation) { 3 }
  let(:last_successful_sync_at) { Time.zone.parse('2026-08-25 11:00:00') }
  let(:current_time) { Time.zone.parse('2026-08-25 12:00:00') }
  let(:lease_context) do
    instance_double(
      Import::Sync::Repositories::ApplicationLease::Context,
      verify_repository!: true,
      verify!: true,
      renew!: true
    )
  end

  let(:issue_response) do
    {
      id: 101,
      number: 4,
      title: 'Issue',
      body: 'Body',
      state: 'open',
      milestone: nil,
      assignees: [],
      labels: [],
      user: nil,
      created_at: 2.days.ago,
      updated_at: 1.hour.ago,
      pull_request: nil
    }
  end

  let(:pull_request_summary) { issue_response.merge(id: 102, number: 5, pull_request: { url: 'redacted' }) }
  let(:pull_request_response) do
    {
      id: 202,
      number: 5,
      title: 'Pull request',
      body: 'PR body',
      state: 'closed',
      milestone: nil,
      assignee: nil,
      user: nil,
      merged_by: nil,
      merged_at: nil,
      created_at: 2.days.ago,
      updated_at: 30.minutes.ago,
      head: { ref: 'feature', sha: 'a' * 40, repo: { id: 10 }, user: { login: 'alice' } },
      base: { ref: 'main', sha: 'b' * 40, repo: { id: 10 } }
    }
  end

  let(:comment_response) do
    {
      id: 303,
      html_url: 'https://github.com/example/connected/issues/4#issuecomment-303',
      body: 'Comment',
      user: nil,
      created_at: 1.day.ago,
      updated_at: 10.minutes.ago
    }
  end

  let(:review_comment_response) do
    {
      id: 404,
      html_url: 'https://github.com/example/connected/pull/5#discussion_r404',
      path: 'README.md',
      commit_id: 'a' * 40,
      original_commit_id: 'a' * 40,
      diff_hunk: "@@ -1 +1 @@\n-Old\n+New",
      body: 'Review comment',
      user: nil,
      line: 1,
      side: 'RIGHT',
      in_reply_to_id: nil,
      subject_type: 'line',
      created_at: 1.day.ago,
      updated_at: 5.minutes.ago
    }
  end

  let(:review_response) do
    { id: 505, state: 'APPROVED', body: nil, user: nil, submitted_at: 20.minutes.ago }
  end

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:git_repository) { instance_double(Repository, fetch_as_mirror: true, commit: true, expire_branches_cache: true) }
  let(:authentication) do
    instance_double(
      Import::Sync::Repositories::Authentication,
      repository_url: 'https://github.com/example/connected.git',
      http_authorization_header: 'Basic redacted',
      resolved_address: ''
    )
  end

  let(:object_reconciler) do
    instance_double(
      Import::Sync::Repositories::WorkItems::ReconcileObjectService,
      execute: true,
      execute_review: nil,
      provider_version_applied?: false,
      listed_version_applied?: false
    )
  end

  let(:allow_cutover) { false }
  let(:now) { -> { current_time } }

  subject(:service) do
    described_class.new(
      repository,
      application_generation: application_generation,
      allow_cutover: allow_cutover,
      now: now
    )
  end

  before do
    allow(Import::Sync::Repositories::WorkItems::ReconcileObjectService)
      .to receive(:new)
      .and_return(object_reconciler)
    allow(object_reconciler).to receive(:execute).with(hash_including(kind: :pull_request)).and_yield.and_return(true)
    allow(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService)
      .to receive(:new)
      .and_return(instance_double(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService, execute: nil))
    allow(Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService).to receive(:new)
      .and_return(instance_double(
        Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService, execute: nil
      ))
    allow(client).to receive(:pull_request).with('example/connected', 5).and_return(pull_request_response)
    allow(client).to receive(:each_page)
      .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([issue_response, pull_request_summary], nil))
    allow(client).to receive(:each_page)
      .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([comment_response], nil))
    allow(client).to receive(:each_page)
      .with(:pull_requests_comments, nil, 'example/connected', hash_including(sort: 'created'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([review_comment_response], nil))
    allow(client).to receive(:each_page)
      .with(:repository_issue_events, nil, 'example/connected', {})
      .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
    allow(client).to receive(:pull_request_reviews).with('example/connected', 5).and_return([review_response])
    allow(authentication).to receive(:client).with(parallel: true).and_return(client)
    allow(Import::Sync::Repositories::Authentication).to receive(:for)
      .with(repository)
      .and_return(authentication)
    allow(repository.project).to receive(:repository).and_return(git_repository)
  end

  # Proves that the repair pass streams all three supported native object types,
  # uses the safety overlap, and checkpoints only after the complete pagination.
  it 'reconciles current issue, pull request, and comment state under the supplied lease' do
    expect(Import::Sync::Repositories::ApplicationLease).not_to receive(:new)
    review_comment_remover = instance_double(
      Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService, execute: nil
    )
    allow(Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService).to receive(:new)
      .with(repository, client: client, lease_context: lease_context)
      .and_return(review_comment_remover)

    result = service.execute(lease_context: lease_context)

    expected_since = (last_successful_sync_at - described_class::SAFETY_OVERLAP).iso8601
    expect(client).to have_received(:each_page).with(
      :issues,
      nil,
      'example/connected',
      state: 'all',
      sort: 'updated',
      direction: 'desc',
      since: expected_since
    )
    expect(client).to have_received(:each_page).with(
      :issues_comments,
      nil,
      'example/connected',
      sort: 'updated',
      direction: 'desc',
      since: expected_since
    )
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue,
      provider_object: issue_response,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Issue)
    )
    expect(object_reconciler).to have_received(:execute).with(
      kind: :pull_request,
      provider_object: pull_request_response,
      representation: an_instance_of(Gitlab::GithubImport::Representation::PullRequest)
    )
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue_comment,
      provider_object: comment_response,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Note)
    )
    expect(client).to have_received(:each_page).with(
      :pull_requests_comments,
      nil,
      'example/connected',
      sort: 'created',
      direction: 'asc',
      since: expected_since
    )
    expect(object_reconciler).to have_received(:execute).with(
      kind: :review_comment,
      provider_object: review_comment_response,
      representation: an_instance_of(Gitlab::GithubImport::Representation::DiffNote)
    )
    expect(object_reconciler).to have_received(:execute_review).with(
      provider_object: review_response,
      representation: an_object_having_attributes(
        review_id: 505, merge_request_iid: 5, note: '', review_type: 'APPROVED'
      )
    )
    expect(review_comment_remover).to have_received(:execute)
    expect(result).to eq(applied_domains: %w[work_items], follow_up: false)
    expect(work_items_state.reload).to have_attributes(
      synced_generation: 2,
      state: 'current',
      last_successful_sync_at: current_time
    )
    expect(lease_context).to have_received(:verify_repository!).with(repository.id)
  end

  # A large provider collection must not monopolize one worker. Each successful
  # page stores the already validated next URL, and a same-generation invocation
  # resumes there without skipping any object or fetching beyond the fixed cap.
  it 'continues a multi-page pass across bounded invocations without skipping a page' do
    stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 2)
    page_two_url = 'https://api.github.com/repositories/1/issues?page=2&per_page=100'
    page_three_url = 'https://api.github.com/repositories/1/issues?page=3&per_page=100'
    second_issue = issue_response.merge(id: 104, number: 6, title: 'Second issue')
    third_issue = issue_response.merge(id: 105, number: 7, title: 'Third issue')
    provider_reads = []

    allow(client).to receive(:each_page)
      .with(:issues, nil, 'example/connected', hash_including(state: 'all')) do |*_args, &block|
        provider_reads << nil
        block.call(Gitlab::GithubImport::Client::Page.new([issue_response], nil, page_two_url))
        provider_reads << page_two_url
        block.call(Gitlab::GithubImport::Client::Page.new([second_issue], page_two_url, page_three_url))
        provider_reads << page_three_url
        block.call(Gitlab::GithubImport::Client::Page.new([third_issue], page_three_url, nil))
      end
    allow(client).to receive(:each_page)
      .with(:issues, page_three_url, 'example/connected', hash_including(state: 'all')) do |*_args, &block|
        provider_reads << page_three_url
        block.call(Gitlab::GithubImport::Client::Page.new([third_issue], page_three_url, nil))
      end

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(provider_reads).to eq([nil, page_two_url])
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
      'phase' => 'issues',
      'page_url' => page_three_url
    )
    expect(work_items_state).to have_attributes(synced_generation: 1, state: 'running')

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(service.execute(lease_context: lease_context))
      .to eq(applied_domains: %w[work_items], follow_up: false)
    expect(provider_reads).to eq([nil, page_two_url, page_three_url])
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue,
      provider_object: issue_response,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Issue)
    ).once
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue,
      provider_object: second_issue,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Issue)
    ).once
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue,
      provider_object: third_issue,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Issue)
    ).once
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current', cursor: nil)
  end

  it 'hands the comments phase to a follow-up when the issues phase used the whole page budget' do
    stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 2)
    review_comment_remover = instance_double(
      Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService, execute: nil
    )
    allow(Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService).to receive(:new)
      .and_return(review_comment_remover)
    page_two_url = 'https://api.github.com/repositories/1/issues?page=2&per_page=100'
    second_issue = issue_response.merge(id: 104, number: 6)
    allow(client).to receive(:each_page)
      .with(:issues, nil, 'example/connected', hash_including(state: 'all')) do |*_args, &block|
        block.call(Gitlab::GithubImport::Client::Page.new([issue_response], nil, page_two_url))
        block.call(Gitlab::GithubImport::Client::Page.new([second_issue], page_two_url, nil))
      end

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(client).not_to have_received(:each_page).with(:issues_comments, anything, 'example/connected', anything)
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor))
      .to include('phase' => 'comments', 'page_url' => nil)
    expect(review_comment_remover).not_to have_received(:execute)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include('phase' => 'events')

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)
    expect(review_comment_remover).to have_received(:execute).once
    expect(client).to have_received(:each_page).with(:issues, nil, 'example/connected', anything).once
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current', cursor: nil)
  end

  it 'continues a multi-page comments phase in a follow-up invocation' do
    stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 2)
    page_two_url = 'https://api.github.com/repositories/1/issues/comments?page=2&per_page=100'
    second_comment = comment_response.merge(id: 304)
    allow(client).to receive(:each_page)
      .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([comment_response], nil, page_two_url))
    allow(client).to receive(:each_page)
      .with(:issues_comments, page_two_url, 'example/connected', hash_including(sort: 'updated'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([second_comment], page_two_url, nil))

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor))
      .to include('phase' => 'comments', 'page_url' => page_two_url)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include('phase' => 'events')

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)
    expect(object_reconciler).to have_received(:execute).with(hash_including(provider_object: second_comment)).once
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current', cursor: nil)
  end

  it 'continues a multi-page review comments phase in a follow-up invocation' do
    stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 3)
    page_two_url = 'https://api.github.com/repositories/1/pulls/comments?page=2&per_page=100'
    second_review_comment = review_comment_response.merge(id: 405)
    allow(client).to receive(:each_page)
      .with(:pull_requests_comments, nil, 'example/connected', hash_including(sort: 'created'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([review_comment_response], nil, page_two_url))
    allow(client).to receive(:each_page)
      .with(:pull_requests_comments, page_two_url, 'example/connected', hash_including(sort: 'created'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([second_review_comment], page_two_url, nil))

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor))
      .to include('phase' => 'review_comments', 'page_url' => page_two_url)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)
    expect(object_reconciler).to have_received(:execute)
      .with(hash_including(kind: :review_comment, provider_object: second_review_comment)).once
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current', cursor: nil)
  end

  it 'does not read reviews of a pull request the pass skipped' do
    allow(object_reconciler).to receive(:execute).with(hash_including(kind: :pull_request)).and_return(nil)

    service.execute(lease_context: lease_context)

    expect(client).not_to have_received(:pull_request_reviews)
    expect(object_reconciler).not_to have_received(:execute_review)
  end

  it 'keeps the GitHub thread of a reply whose parent is not mapped' do
    reply = review_comment_response.merge(id: 406, in_reply_to_id: 404)
    allow(client).to receive(:each_page)
      .with(:pull_requests_comments, nil, 'example/connected', hash_including(sort: 'created'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([reply], nil))
    allow(object_reconciler).to receive(:review_comment_discussion_id).with(404).and_return(nil)

    service.execute(lease_context: lease_context)

    expect(object_reconciler).to have_received(:execute).with(
      kind: :review_comment,
      provider_object: reply,
      representation: an_instance_of(Gitlab::GithubImport::Representation::DiffNote)
    )
  end

  it 'skips pending reviews' do
    allow(client).to receive(:pull_request_reviews)
      .and_return([review_response.merge(id: 506, state: 'PENDING', submitted_at: nil), review_response])

    service.execute(lease_context: lease_context)

    expect(object_reconciler).to have_received(:execute_review).once
    expect(object_reconciler).to have_received(:execute_review).with(hash_including(provider_object: review_response))
  end

  context 'when there is nothing to apply' do
    it 'does nothing when GitHub updates are not active' do
      repository.update!(authority_state: :gitlab_canonical)

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: false)
      expect(client).not_to have_received(:each_page)
      expect(work_items_state.reload).to have_attributes(state: 'pending', synced_generation: 1)
    end

    it 'does nothing when the domain is already current' do
      work_items_state.update!(synced_generation: 2, state: :current)

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: false)
      expect(client).not_to have_received(:each_page)
    end
  end

  # A provider pass may take longer than the overlap window. The checkpoint is
  # therefore the instant the pass began, so an object changed after its page
  # was read remains inside the next query instead of being skipped forever.
  it 'checkpoints the pass start instead of its later completion time' do
    pass_started_at = current_time
    pass_completed_at = current_time + 10.minutes
    current_clock = pass_started_at
    allow(now).to receive(:call) { current_clock }
    allow(object_reconciler).to receive(:execute) { current_clock = pass_completed_at }

    service.execute(lease_context: lease_context)

    expect(work_items_state.reload).to have_attributes(
      last_sync_started_at: pass_started_at,
      last_successful_sync_at: pass_started_at
    )
  end

  # Simulates quota exhaustion only after two comment pages were fully applied.
  # Retry must skip the completed issues phase, start at the first unapplied page,
  # and continue without persisting the provider exception detail.
  it 'resumes the next provider page after a rate-limit failure' do
    stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 10)
    page_two_url = 'https://api.github.com/repositories/1/issues/comments?page=2&per_page=100'
    page_three_url = 'https://api.github.com/repositories/1/issues/comments?page=3&per_page=100'
    second_comment = comment_response.merge(
      id: 304,
      html_url: 'https://github.com/example/connected/issues/4#issuecomment-304'
    )
    third_comment = comment_response.merge(
      id: 305,
      html_url: 'https://github.com/example/connected/issues/4#issuecomment-305'
    )
    cursor_at_comment_start = nil

    allow(client).to receive(:each_page)
      .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated')) do |*_args, &block|
        cursor_at_comment_start = Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)
        block.call(Gitlab::GithubImport::Client::Page.new([comment_response], nil, page_two_url))
        block.call(Gitlab::GithubImport::Client::Page.new([second_comment], page_two_url, page_three_url))
        raise Gitlab::GithubImport::RateLimitError, 'rate limited provider response'
      end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Gitlab::GithubImport::RateLimitError, 'rate limited provider response')

    persisted_cursor = Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)
    expect(cursor_at_comment_start).to include(
      'generation' => 2,
      'phase' => 'comments',
      'page_url' => nil
    )
    expect(persisted_cursor).to include(
      'generation' => 2,
      'started_at' => current_time.iso8601(6),
      'since' => (last_successful_sync_at - described_class::SAFETY_OVERLAP).iso8601(6),
      'phase' => 'comments',
      'page_url' => page_three_url
    )
    expect(work_items_state).to have_attributes(
      synced_generation: 1,
      state: 'delayed',
      last_error_code: 'github_rate_limited',
      last_error_message: 'GitHub rate limit reached'
    )
    expect(work_items_state.cursor).not_to include('rate limited provider response')

    allow(client).to receive(:each_page)
      .with(:issues_comments, page_three_url, 'example/connected', hash_including(sort: 'updated'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([third_comment], page_three_url))

    expect(service.execute(lease_context: lease_context))
      .to eq(applied_domains: %w[work_items], follow_up: false)

    expect(client).to have_received(:each_page)
      .with(:issues, nil, 'example/connected', hash_including(state: 'all')).once
    expect(client).to have_received(:each_page)
      .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated')).once
    expect(client).to have_received(:each_page)
      .with(:issues_comments, page_three_url, 'example/connected', hash_including(sort: 'updated')).once
    expect(object_reconciler).to have_received(:execute).with(
      kind: :issue_comment,
      provider_object: second_comment,
      representation: an_instance_of(Gitlab::GithubImport::Representation::Note)
    ).once
    expect(work_items_state.reload).to have_attributes(
      synced_generation: 2,
      state: 'current',
      cursor: nil,
      last_successful_sync_at: current_time
    )
  end

  # Advances desired work while generation two is already scanning. The running
  # cursor must finish generation two, then disappear so the follow-up performs
  # a new full overlapping pass for generation three instead of resuming old pages.
  it 'finishes its captured generation before a coalesced follow-up starts fresh' do
    advanced_generation = false
    captured_cursor = nil
    allow(object_reconciler).to receive(:execute) do
      next if advanced_generation

      advanced_generation = true
      work_items_state.update!(desired_generation: 3)
      captured_cursor = Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)
    end

    first_result = service.execute(lease_context: lease_context)

    expect(first_result).to eq(applied_domains: %w[work_items], follow_up: true)
    expect(captured_cursor).to include('generation' => 2, 'started_at' => current_time.iso8601(6))
    expect(work_items_state.reload).to have_attributes(
      desired_generation: 3,
      synced_generation: 2,
      state: 'pending',
      cursor: nil,
      last_successful_sync_at: current_time
    )
    expect(work_items_state).to be_lagging
    expect(work_items_state.synced_generation).to be < work_items_state.desired_generation

    second_result = service.execute(lease_context: lease_context)

    expect(second_result).to eq(applied_domains: %w[work_items], follow_up: false)
    expect(client).to have_received(:each_page).with(
      :issues,
      nil,
      'example/connected',
      hash_including(since: (last_successful_sync_at - described_class::SAFETY_OVERLAP).iso8601)
    ).once
    expect(client).to have_received(:each_page).with(
      :issues,
      nil,
      'example/connected',
      hash_including(since: (current_time - described_class::SAFETY_OVERLAP).iso8601)
    ).once
    expect(work_items_state.reload).to have_attributes(
      desired_generation: 3,
      synced_generation: 3,
      state: 'current',
      cursor: nil,
      last_successful_sync_at: current_time
    )
  end

  # A persisted cursor is an internal request coordinate. One this code cannot read is
  # dropped and the pass restarts from scratch, so a bad row cannot wedge the domain.
  context 'when the persisted cursor cannot be read' do
    where(:description, :cursor) do
      'malformed JSON' | '{"generation":1'
      'missing fields' | '{"generation":2}'
    end

    with_them do
      it 'discards the cursor, logs it without its contents and restarts the pass' do
        work_items_state.update!(cursor: cursor, state: :pending)
        expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
          message: 'discarding invalid GitHub work item cursor',
          import_sync_repository_id: repository.id,
          Labkit::Fields::GL_PROJECT_ID => repository.project.id,
          domain: 'work_items'
        )

        expect(service.execute(lease_context: lease_context))
          .to eq(applied_domains: %w[work_items], follow_up: false)

        expect(client).to have_received(:each_page).with(:issues, nil, 'example/connected', anything)
        expect(work_items_state.reload).to have_attributes(synced_generation: 2, cursor: nil, state: 'current')
      end
    end
  end

  # A superseded writer (the application generation was bumped while it was
  # applying a page) must not checkpoint the cursor or advance the generation,
  # regardless of what the cursor row looks like.
  it 'stops a writer with a stale application generation from checkpointing progress' do
    page_two_url = 'https://api.github.com/repositories/1/issues?page=2&per_page=100'
    cursor_at_page = nil
    allow(client).to receive(:each_page)
      .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
      .and_yield(Gitlab::GithubImport::Client::Page.new([issue_response], nil, page_two_url))
    expect(client).not_to receive(:each_page)
      .with(:issues_comments, anything, 'example/connected', anything)
    allow(object_reconciler).to receive(:execute) do
      cursor_at_page = work_items_state.reload.cursor
      repository.update!(application_generation: application_generation + 1)
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(
        Import::Sync::Errors::StaleApplicationError,
        'GitHub updates changed while work item progress was being saved'
      )

    expect(cursor_at_page).to be_present
    expect(work_items_state.reload.cursor).to eq(cursor_at_page)
    expect(work_items_state).to have_attributes(synced_generation: 1)
  end

  # Once the generation moved on, the cursor row is no longer consulted for
  # comparison: a cursor advanced by someone else does not fail this writer.
  it 'does not compare the cursor row against the writer\'s own copy' do
    newer_page_url = 'https://api.github.com/repositories/1/issues?page=3&per_page=100'
    allow(object_reconciler).to receive(:execute) do
      newer_cursor = Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)
      newer_cursor['page_url'] = newer_page_url
      work_items_state.update!(cursor: Gitlab::Json.generate(newer_cursor))
    end

    expect(service.execute(lease_context: lease_context))
      .to eq(applied_domains: %w[work_items], follow_up: false)
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, cursor: nil)
  end

  it 'discards a leftover cursor from a finished generation and restarts the pass' do
    work_items_state.update!(
      cursor: Gitlab::Json.generate(
        generation: 1, started_at: 1.day.ago.iso8601(6), since: nil, phase: 'comments', page_url: nil
      )
    )

    expect(service.execute(lease_context: lease_context))
      .to eq(applied_domains: %w[work_items], follow_up: false)

    expect(client).to have_received(:each_page).with(:issues, nil, 'example/connected', anything)
    expect(work_items_state.reload).to have_attributes(synced_generation: 2, cursor: nil, state: 'current')
  end

  it 'reads without a window when the resumed cursor has none' do
    work_items_state.update!(
      cursor: Gitlab::Json.generate(
        generation: 2, started_at: current_time.iso8601(6), since: nil, phase: 'issues', page_url: nil
      )
    )

    service.execute(lease_context: lease_context)

    expect(client).to have_received(:each_page)
      .with(:issues, nil, 'example/connected', state: 'all', sort: 'updated', direction: 'desc')
    expect(client).to have_received(:each_page)
      .with(:issues_comments, nil, 'example/connected', sort: 'updated', direction: 'desc')
  end

  it 'does not checkpoint when another writer cleared the cursor mid-pass' do
    allow(object_reconciler).to receive(:execute) do
      work_items_state.reload.update!(cursor: nil)
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /progress changed/)

    expect(work_items_state.reload).to have_attributes(cursor: nil, synced_generation: 1, state: 'degraded')
  end

  it 'does not resurrect a cursor after the pass was completed by another writer' do
    allow(object_reconciler).to receive(:execute) do
      work_items_state.reload.update!(synced_generation: 2, cursor: nil, state: :current)
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /progress changed/)

    expect(work_items_state.reload.cursor).to be_nil
  end

  it 'does not overwrite a cursor that belongs to another generation' do
    other = Gitlab::Json.generate(
      generation: 2, started_at: current_time.iso8601(6), since: nil, phase: 'issues', page_url: nil
    )
    allow(object_reconciler).to receive(:execute) do
      work_items_state.reload.update!(desired_generation: 3, cursor: other.sub('"generation":2', '"generation":3'))
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /progress changed/)

    expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include('generation' => 3)
  end

  it 'refuses to complete a pass whose persisted cursor is not in the events phase' do
    allow(object_reconciler).to receive(:execute)
    allow(service).to receive(:reconcile_events) do |cursor, _lease_context|
      work_items_state.reload.update!(cursor: work_items_state.cursor.sub('"events"', '"issues"'))
      cursor
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /before checkpointing/)

    expect(work_items_state.reload.synced_generation).to eq(1)
  end

  it 'does not advance the generation when the application generation changes before the final write' do
    allow(service).to receive(:apply_success).and_wrap_original do |original, target|
      repository.update!(application_generation: application_generation + 1)
      original.call(target)
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError, /while work items were being applied/)

    expect(work_items_state.reload).to have_attributes(synced_generation: 1, state: 'degraded')
    expect(Gitlab::Json::SafeParser.parse(work_items_state.cursor)).to include('phase' => 'events')
  end

  context 'when a pull request comes from a fork' do
    before do
      pull_request_response[:head][:repo][:id] = 11
    end

    # A fork head is not present under the base repository's normal heads. The
    # current hidden PR ref must be fetched before rebuilding the MR diff.
    it 'fetches the current pull request head through authenticated Git transport' do
      service.execute(lease_context: lease_context)

      expect(git_repository).to have_received(:fetch_as_mirror).with(
        'https://github.com/example/connected.git',
        refmap: ['+refs/pull/5/head:refs/merge-requests/5/head'],
        forced: true,
        no_tags: true,
        prune: false,
        http_authorization_header: 'Basic redacted',
        resolved_address: ''
      )
      expect(git_repository).not_to have_received(:expire_branches_cache)
    end

    # The importer creates a missing fork branch through add_branch, which runs the Git hooks.
    # Writing the branch from the fetch makes that step a no-op, so no pipeline starts from the fork.
    it 'writes the fork branch from the fetch for an open pull request' do
      pull_request_response[:state] = 'open'

      service.execute(lease_context: lease_context)

      expect(git_repository).to have_received(:fetch_as_mirror).with(
        'https://github.com/example/connected.git',
        hash_including(refmap: [
          '+refs/pull/5/head:refs/merge-requests/5/head',
          '+refs/pull/5/head:refs/heads/github/fork/alice/feature'
        ])
      )
      expect(git_repository).to have_received(:expire_branches_cache)
    end

    # Without the fork owner the importer names the branch after the bare source branch, and a forced
    # write to that name could overwrite a base repository branch.
    it 'does not write a branch when the fork owner is gone and the name leaves the fork namespace' do
      pull_request_response[:state] = 'open'
      pull_request_response[:head][:user] = nil

      service.execute(lease_context: lease_context)

      expect(git_repository).to have_received(:fetch_as_mirror).with(
        'https://github.com/example/connected.git',
        hash_including(refmap: ['+refs/pull/5/head:refs/merge-requests/5/head'])
      )
      expect(git_repository).not_to have_received(:expire_branches_cache)
    end

    it 'does not fetch the pull request head when the mapping already has this provider version' do
      allow(object_reconciler).to receive(:provider_version_applied?)
        .with(kind: :pull_request, provider_object: pull_request_response, representation: anything)
        .and_return(true)

      service.execute(lease_context: lease_context)

      expect(git_repository).not_to have_received(:fetch_as_mirror)
      expect(object_reconciler).to have_received(:execute).with(hash_including(kind: :pull_request))
    end

    it 'does not fetch when the pull request number is not a positive integer' do
      [nil, 0].each do |number|
        pull_request_response[:number] = number

        expect { service.execute(lease_context: lease_context) }
          .to raise_error(ArgumentError, 'GitHub pull request identity is invalid')
      end

      expect(git_repository).not_to have_received(:fetch_as_mirror)
    end

    # Once the issues phase checkpoints, its fork refs are durable page work. A
    # comment-phase retry must resume directly from that cursor and must not
    # refetch the already completed issues page.
    it 'does not refetch the fork ref when retry resumes in the comments phase' do
      comment_attempts = 0
      allow(client).to receive(:each_page)
        .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated')) do |*_args, &block|
          comment_attempts += 1
          raise Gitlab::GithubImport::RateLimitError, 'rate limited provider response' if comment_attempts == 1

          block.call(Gitlab::GithubImport::Client::Page.new([comment_response], nil))
        end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Gitlab::GithubImport::RateLimitError, 'rate limited provider response')
      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
        'phase' => 'comments',
        'page_url' => nil
      )

      expect(service.execute(lease_context: lease_context))
        .to eq(applied_domains: %w[work_items], follow_up: false)

      expect(client).to have_received(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(state: 'all')).once
      expect(git_repository).to have_received(:fetch_as_mirror).once
    end
  end

  # A same-repo head can be unreachable too, once its branch was deleted on GitHub between passes.
  # Rebuilding without the commit would replace the diff with an empty one.
  context 'when a same-repo pull request head is missing locally' do
    before do
      allow(git_repository).to receive(:commit).with('a' * 40).and_return(nil)
    end

    it 'fetches the pull request head without writing a branch' do
      service.execute(lease_context: lease_context)

      expect(git_repository).to have_received(:fetch_as_mirror).with(
        'https://github.com/example/connected.git',
        hash_including(refmap: ['+refs/pull/5/head:refs/merge-requests/5/head'])
      )
      expect(git_repository).not_to have_received(:expire_branches_cache)
    end
  end

  it 'does not fetch a same-repo pull request head that is already present' do
    service.execute(lease_context: lease_context)

    expect(git_repository).to have_received(:commit).with('a' * 40)
    expect(git_repository).not_to have_received(:fetch_as_mirror)
  end

  it 'does not read a pull request the issues list shows as already applied' do
    allow(object_reconciler).to receive(:listed_version_applied?).with(pull_request_summary).and_return(true)

    expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)

    expect(client).not_to have_received(:pull_request)
    expect(client).not_to have_received(:pull_request_reviews)
    expect(object_reconciler).not_to have_received(:execute).with(hash_including(kind: :pull_request))
    expect(object_reconciler).to have_received(:execute).with(hash_including(kind: :issue))
  end

  context 'when checking for comments deleted on GitHub' do
    let(:local_issue) { instance_double(Issue) }
    let(:local_merge_request) { instance_double(MergeRequest) }
    let(:comment_remover) do
      instance_double(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService, execute: nil)
    end

    before do
      allow(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService)
        .to receive(:new)
        .and_return(comment_remover)
    end

    it 'checks every reconciled issue and pull request' do
      allow(object_reconciler).to receive(:execute).with(hash_including(kind: :issue)).and_return(local_issue)
      allow(object_reconciler).to receive(:execute).with(hash_including(kind: :pull_request))
        .and_return(local_merge_request)

      service.execute(lease_context: lease_context)

      expect(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService).to have_received(:new)
        .with(repository, client: client, lease_context: lease_context)
      expect(comment_remover).to have_received(:execute).with(local_issue, issue_response, unchanged: false)
      expect(comment_remover).to have_received(:execute)
        .with(local_merge_request, pull_request_summary, unchanged: false)
    end

    it 'checks a pull request the issues list shows as already applied' do
      allow(git_repository).to receive_messages(exists?: false, empty?: true)
      merge_request = create(:merge_request, :skip_diff_creation, source_project: repository.project, iid: 5)
      allow(object_reconciler).to receive(:listed_version_applied?).with(pull_request_summary).and_return(true)

      service.execute(lease_context: lease_context)

      expect(comment_remover).to have_received(:execute).with(merge_request, pull_request_summary, unchanged: true)
    end

    it 'tells the check whether the object changed before it was reconciled' do
      allow(object_reconciler).to receive(:execute).with(hash_including(kind: :issue)).and_return(local_issue)
      allow(object_reconciler).to receive(:listed_version_applied?).with(issue_response).and_return(true)

      service.execute(lease_context: lease_context)

      expect(comment_remover).to have_received(:execute).with(local_issue, issue_response, unchanged: true)
    end

    it 'does not check an object the reconciler skipped' do
      allow(object_reconciler).to receive(:execute).and_return(nil)

      service.execute(lease_context: lease_context)

      expect(comment_remover).not_to have_received(:execute)
    end
  end

  context 'when no pass has succeeded yet' do
    let(:last_successful_sync_at) { nil }

    it 'starts the window at the sync repository creation instead of reading the whole history' do
      service.execute(lease_context: lease_context)

      expected_since = (repository.created_at - described_class::SAFETY_OVERLAP).iso8601
      expect(client).to have_received(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(since: expected_since))
      expect(client).to have_received(:each_page)
        .with(:issues_comments, nil, 'example/connected', hash_including(since: expected_since))
    end
  end

  context 'when reconciliation creates placeholder-user references' do
    let(:import_state) { instance_double(ProjectImportState, id: 91) }
    let(:issue_page_url) { 'https://api.github.com/repositories/1/issues?page=1&per_page=100' }
    let(:comment_page_url) { 'https://api.github.com/repositories/1/issues/comments?page=1&per_page=100' }
    let(:placeholder_reference_store) do
      instance_double(Import::PlaceholderReferences::Store, any?: true)
    end

    let(:placeholder_load_result) do
      ServiceResponse.success(payload: { processed_count: 1, error_count: 0 })
    end

    let(:placeholder_load_service) do
      instance_double(Import::PlaceholderReferences::LoadService, execute: placeholder_load_result)
    end

    before do
      allow(repository.project).to receive_messages(
        import_state: import_state,
        placeholder_reference_store: placeholder_reference_store
      )
      allow(client).to receive(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([issue_response], issue_page_url))
      allow(client).to receive(:each_page)
        .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([comment_response], comment_page_url))
      allow(Import::PlaceholderReferences::LoadService).to receive(:new)
        .with(import_source: Import::SOURCE_GITHUB, import_uid: import_state.id)
        .and_return(placeholder_load_service)
    end

    # Each completed provider page must synchronously drain its Redis references
    # before persisting that page coordinate. The assertion at the persistence
    # boundary proves enqueue success is no longer mistaken for durable storage.
    it 'durably loads references before each page checkpoint' do
      completed_loads = 0
      allow(placeholder_load_service).to receive(:execute) do
        completed_loads += 1
        placeholder_load_result
      end
      allow(service).to receive(:persist_cursor!).and_wrap_original do |original, cursor, **options|
        expected_loads = 1 if cursor[:page_url] == issue_page_url
        expected_loads = 2 if cursor[:page_url] == comment_page_url
        expect(completed_loads).to eq(expected_loads) if expected_loads

        original.call(cursor, **options)
      end
      expect(Import::LoadPlaceholderReferencesWorker).not_to receive(:perform_async)

      service.execute(lease_context: lease_context)

      expect(Import::PlaceholderReferences::LoadService).to have_received(:new).exactly(4).times
      expect(placeholder_load_service).to have_received(:execute).exactly(4).times
    end

    # A provider failure after page one must retain its resume coordinate only
    # after that page's references reached PostgreSQL. Loading only at the end of
    # the pass would leave completed-page references exposed to the Redis TTL.
    it 'durably loads a completed page even when a later page fails' do
      allow(client).to receive(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(state: 'all')) do |*_args, &block|
          block.call(Gitlab::GithubImport::Client::Page.new([issue_response], issue_page_url))
          raise Gitlab::GithubImport::RateLimitError, 'rate limited provider response'
        end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Gitlab::GithubImport::RateLimitError, 'rate limited provider response')

      expect(placeholder_load_service).to have_received(:execute).once
      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
        'phase' => 'issues',
        'page_url' => issue_page_url
      )
    end

    # Loader failure occurs after importer mutations but before the page CAS.
    # The old coordinate and generation must remain durable so retry revisits the
    # page and regenerates every reference instead of declaring incomplete success.
    it 'does not advance the page cursor or generation when durable loading fails' do
      allow(placeholder_load_service).to receive(:execute).and_raise(Redis::ConnectionError, 'cache unavailable')
      expect(client).not_to receive(:each_page)
        .with(:issues_comments, anything, 'example/connected', anything)
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        instance_of(Redis::ConnectionError),
        import_sync_repository_id: repository.id,
        project_id: repository.project.id
      )

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(
          Import::Sync::Errors::PlaceholderReferenceLoadError,
          described_class::PLACEHOLDER_LOAD_FAILURE_MESSAGE
        )

      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
        'phase' => 'issues',
        'page_url' => nil
      )
      expect(work_items_state).to have_attributes(
        synced_generation: 1,
        state: 'degraded',
        last_error_code: 'github_work_items_update_failed',
        last_error_message: 'GitHub work item update failed'
      )
    end

    it 'does not checkpoint the page when some references failed to load' do
      allow(placeholder_load_service).to receive(:execute)
        .and_return(ServiceResponse.success(payload: { processed_count: 1, error_count: 1 }))
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(
          Import::Sync::Errors::PlaceholderReferenceLoadError,
          described_class::PLACEHOLDER_LOAD_FAILURE_MESSAGE
        )

      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
        'phase' => 'issues',
        'page_url' => nil
      )
    end
  end

  context 'when the project has no import data' do
    let(:github_author) { { id: 501, login: 'source-author' } }
    let(:issue_response) { super().merge(user: github_author) }

    before do
      allow(Import::Sync::Repositories::Authentication).to receive(:for).with(repository).and_call_original
      repository.project.import_data&.destroy!
      repository.project.association(:import_data).reset
    end

    # The token is read from ProjectImportData at the point of use. Without it the
    # pass must fail with a fixed error before any provider or Git work starts.
    it 'raises a missing credentials error and attempts nothing else' do
      expect(Import::Sync::Repositories::WorkItems::ReconcileObjectService).not_to receive(:new)
      expect(client).not_to receive(:each_page)

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Errors::MissingCredentialsError, 'Project import data is missing')

      expect(work_items_state.reload).to have_attributes(
        synced_generation: 1,
        state: 'degraded',
        last_error_code: 'github_work_items_update_failed',
        last_error_message: 'GitHub work item update failed'
      )
    end
  end

  # A failure after partial application intentionally leaves the old generation;
  # retry replays through durable mappings and the UI receives no provider detail.
  it 'retains its checkpoint and records sanitized health when an object fails' do
    allow(object_reconciler).to receive(:execute).and_raise(StandardError, 'secret provider detail')

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(StandardError, 'secret provider detail')

    expect(work_items_state.reload).to have_attributes(
      synced_generation: 1,
      state: 'degraded',
      last_error_code: 'github_work_items_update_failed',
      last_error_message: 'GitHub work item update failed'
    )
  end

  # Once the distributed application fence is lost this process no longer owns
  # any repository mutation, including health bookkeeping.
  it 'does not write health state after losing the application lease' do
    allow(object_reconciler).to receive(:execute)
      .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

    expect(work_items_state.reload).to have_attributes(
      synced_generation: 1,
      state: 'running',
      last_error_code: nil,
      last_error_message: nil
    )
  end

  context 'when running the final cut-over' do
    let(:authority_state) { :cutting_over }
    let(:allow_cutover) { true }

    # Stop-updates catch-up is the sole non-provider-canonical application path;
    # it still requires the same captured generation and application lease.
    it 'allows the final work-item pass when explicitly requested' do
      expect(service.execute(lease_context: lease_context))
        .to eq(applied_domains: %w[work_items], follow_up: false)
    end

    context 'when the final pass is not requested' do
      let(:allow_cutover) { false }

      it 'does nothing for a regular pass' do
        expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: false)
        expect(client).not_to have_received(:each_page)
        expect(work_items_state.reload).to have_attributes(state: 'pending', synced_generation: 1)
      end
    end
  end

  it 'logs only ids, the domain and the health state when a pass fails' do
    allow(object_reconciler).to receive(:execute).and_raise(StandardError, 'secret provider detail')

    expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
      message: 'GitHub work item reconciliation failed',
      import_sync_repository_id: repository.id,
      Labkit::Fields::GL_PROJECT_ID => repository.project.id,
      Labkit::Fields::ERROR_TYPE => 'StandardError',
      domain: 'work_items',
      last_error_code: 'github_work_items_update_failed',
      health_state: 'degraded'
    )

    expect { service.execute(lease_context: lease_context) }.to raise_error(StandardError)
  end

  it 'counts the failed pass by domain and health state' do
    allow(object_reconciler).to receive(:execute).and_raise(StandardError)
    counter = instance_double(Prometheus::Client::Counter, increment: nil)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter).with(:gitlab_import_sync_reconcile_failures_total, anything)
      .and_return(counter)

    expect { service.execute(lease_context: lease_context) }.to raise_error(StandardError)

    expect(counter).to have_received(:increment).with(domain: 'work_items', health_state: 'degraded').once
  end

  it 'pauses instead of degrading when authority left provider_canonical during the pass' do
    allow(object_reconciler).to receive(:execute) do
      repository.update!(authority_state: :gitlab_canonical)
    end

    expect { service.execute(lease_context: lease_context) }
      .to raise_error(Import::Sync::Errors::StaleApplicationError)

    expect(work_items_state.reload).to have_attributes(
      state: 'paused',
      last_error_code: 'github_updates_inactive',
      synced_generation: 1
    )
  end

  context 'with lease renewal and verification' do
    # Attachment rewrites and diff rebuilds can make one page outlast the 5 minute
    # lease, so the lease is extended before each object and after each pull request read.
    it 'renews the lease before every object and after each pull request fetch' do
      calls = []
      allow(lease_context).to receive(:renew!) { calls << :renew }
      allow(client).to receive(:pull_request) do
        calls << :pull_request
        pull_request_response
      end
      allow(client).to receive(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(state: 'all')) do |*_args, &block|
          calls << :issues_page_one
          block.call(Gitlab::GithubImport::Client::Page.new([issue_response, pull_request_summary], nil, 'https://api.github.com/x?page=2'))
        end

      service.execute(lease_context: lease_context)

      expect(calls).to eq(%i[issues_page_one renew renew pull_request renew renew renew renew])
    end

    it 'renews the lease at the start of every comments page' do
      comment_pages = 0
      allow(client).to receive(:each_page)
        .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated')) do |*_args, &block|
          comment_pages += 1
          block.call(Gitlab::GithubImport::Client::Page.new([comment_response], nil, 'https://api.github.com/c?page=2'))
        end
      stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 10)

      service.execute(lease_context: lease_context)

      expect(comment_pages).to eq(1)
      expect(lease_context).to have_received(:renew!).at_least(:twice)
    end

    it 'writes no state when the lease was already lost at the start' do
      allow(lease_context).to receive(:verify_repository!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(work_items_state.reload).to have_attributes(state: 'pending', cursor: nil, synced_generation: 1)
    end

    it 'does not checkpoint the cursor when the lease is lost before the write' do
      verify_calls = 0
      allow(lease_context).to receive(:verify!) do
        verify_calls += 1
        raise Import::Sync::Repositories::ApplicationLease::LostLeaseError if verify_calls == 2
      end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor)).to include(
        'phase' => 'issues',
        'page_url' => nil
      )
      expect(work_items_state).to have_attributes(synced_generation: 1, state: 'running', last_error_code: nil)
    end

    it 'does not advance the generation when the lease is lost before the final fence' do
      verify_calls = 0
      allow(lease_context).to receive(:verify!) do
        verify_calls += 1
        raise Import::Sync::Repositories::ApplicationLease::LostLeaseError if verify_calls == 4
      end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

      expect(work_items_state.reload.synced_generation).to eq(1)
    end
  end

  context 'when a fork pull request goes stale before its ref is fetched' do
    before do
      pull_request_response[:head][:repo][:id] = 11
    end

    # The pre-write check sits immediately before the hidden-ref fetch, so a
    # superseded writer cannot update refs/merge-requests/<iid>/head.
    it 'skips the fetch and raises when the application generation changed' do
      allow(client).to receive(:pull_request) do
        repository.update!(application_generation: application_generation + 1)
        pull_request_response
      end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Errors::StaleApplicationError, /generation changed/)

      expect(git_repository).not_to have_received(:fetch_as_mirror)
      expect(object_reconciler).not_to have_received(:execute).with(hash_including(kind: :pull_request))
      expect(work_items_state.reload.synced_generation).to eq(1)
    end

    it 'skips the fetch when authority left provider_canonical' do
      allow(client).to receive(:pull_request) do
        repository.update!(authority_state: :gitlab_canonical)
        pull_request_response
      end

      expect { service.execute(lease_context: lease_context) }
        .to raise_error(Import::Sync::Errors::StaleApplicationError)

      expect(git_repository).not_to have_received(:fetch_as_mirror)
    end

    it 'renews the lease after the pull request read and after the ref fetch' do
      calls = []
      allow(lease_context).to receive(:renew!) { calls << :renew }
      allow(client).to receive(:pull_request) do
        calls << :pull_request
        pull_request_response
      end
      allow(git_repository).to receive(:fetch_as_mirror) { calls << :fetch }

      service.execute(lease_context: lease_context)

      expect(calls.first(5)).to eq(%i[renew renew pull_request renew fetch])
      expect(calls[5]).to eq(:renew)
    end
  end

  context 'when the initial import already mapped the GitHub data', :clean_gitlab_redis_shared_state do
    include Import::UserMappingHelper

    let_it_be_with_reload(:project) do
      create(:project, :repository, :in_group, :github_import, :import_user_mapping_enabled)
    end

    let(:authority_state) { :provisioning }
    let(:created_at) { Time.utc(2026, 8, 20, 9, 0, 0) }
    let(:updated_at) { Time.utc(2026, 8, 25, 11, 0, 0) }
    let(:repository) do
      create(:import_sync_repository, :oauth, project: project, authority_state: authority_state,
        application_generation: application_generation, provider_full_name: 'example/connected')
    end

    let(:issue_response) { super().merge(created_at: created_at, updated_at: updated_at, comments: 1) }
    let(:pull_request_summary) { super().merge(comments: 0) }
    let(:pull_request_response) do
      super().merge(
        created_at: created_at,
        updated_at: updated_at,
        head: {
          ref: 'feature', sha: project.repository.commit('feature').id, repo: { id: 10 }, user: { login: 'alice' }
        },
        base: { ref: 'master', sha: project.repository.commit('master').id, repo: { id: 10 } }
      )
    end

    let(:comment_response) { super().merge(created_at: created_at, updated_at: updated_at) }
    let(:review_response) do
      super().merge(user: { id: 601, login: 'reviewer' }, body: 'Looks good', submitted_at: updated_at)
    end

    let(:issue_event) do
      Gitlab::GithubImport::Representation::IssueEvent.new(
        id: comment_response[:id],
        actor: nil,
        event: 'commented',
        created_at: created_at,
        updated_at: updated_at,
        body: comment_response[:body],
        issue: { number: issue_response[:number], pull_request: false }
      )
    end

    let(:issue_representation) do
      Gitlab::GithubImport::Representation::Issue.from_api_response(
        issue_response,
        work_item_type_id: build(:work_item_system_defined_type, :issue).id
      )
    end

    before do
      allow(repository.project).to receive(:repository).and_call_original
      project.build_or_assign_import_data(
        data: { 'optional_stages' => { 'continuous_sync' => true }, 'user_contribution_mapping_enabled' => true }
      ).save!
      repository
      Users::Internal.in_organization(project.organization_id).ghost
      allow(client).to receive_messages(web_endpoint: 'https://github.com/', user: review_response[:user])
      allow(Import::Sync::Repositories::WorkItems::ReconcileObjectService).to receive(:new).and_call_original
      allow(Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService).to receive(:new).and_call_original
      allow_next_instance_of(Gitlab::GithubImport::Importer::PullRequestImporter) do |importer|
        allow(importer).to receive(:insert_git_data)
      end

      Gitlab::GithubImport::Importer::IssueImporter.new(issue_representation, project, client).execute
      Gitlab::GithubImport::Importer::PullRequestImporter.new(
        Gitlab::GithubImport::Representation::PullRequest.from_api_response(pull_request_response),
        project,
        client
      ).execute
      Gitlab::GithubImport::Importer::Events::Commented.new(project, client).execute(issue_event)
      Gitlab::GithubImport::Importer::DiffNoteImporter.new(
        Gitlab::GithubImport::Representation::DiffNote.from_api_response(review_comment_response),
        project,
        client
      ).execute
      review_event = Gitlab::GithubImport::Representation::IssueEvent.new(
        id: review_response[:id],
        actor: review_response[:user],
        event: 'reviewed',
        state: 'approved',
        body: 'Looks good',
        created_at: updated_at,
        submitted_at: updated_at.iso8601,
        issue: { number: pull_request_response[:number], pull_request: true }
      )
      Gitlab::GithubImport::Importer::Events::Reviewed.new(project, client).execute(review_event)

      repository.update!(authority_state: :provider_canonical)
    end

    it 'has one mapping for each imported record' do
      expect(Import::Sync::ExternalObject.where(project_id: project.id).group(:kind).count)
        .to eq('issue' => 1, 'pull_request' => 1, 'issue_comment' => 1, 'review_comment' => 1, 'review' => 1)
    end

    # The sync engine matches only through mappings, so a first pass over data the
    # initial import already brought in must be a no-op.
    it 'creates nothing and touches no matching record in the first sync pass' do
      issue = project.issues.find_by!(iid: issue_response[:number])
      merge_request = project.merge_requests.find_by!(iid: pull_request_response[:number])
      note = project.notes.find_by!(noteable: issue)
      snapshots = [issue, merge_request, note].map { |record| record.attributes.merge('class' => record.class.name) }

      [
        Gitlab::GithubImport::Importer::IssueImporter,
        Gitlab::GithubImport::Importer::PullRequestImporter,
        Gitlab::GithubImport::Importer::NoteImporter,
        Gitlab::GithubImport::Importer::DiffNoteImporter
      ].each do |importer_class|
        allow(importer_class).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |importer|
            expect(importer).not_to receive(:execute)
            expect(importer).not_to receive(:insert_git_data)
          end
        end
      end

      expect { service.execute(lease_context: lease_context) }
        .to not_change { Issue.count }
        .and not_change { MergeRequest.count }
        .and not_change { Note.count }
        .and not_change { Approval.count }
        .and not_change { Import::Sync::ExternalObject.count }

      expect([issue.reload, merge_request.reload, note.reload].map { |r| r.attributes.merge('class' => r.class.name) })
        .to eq(snapshots)
      expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current', cursor: nil)
    end

    it 'does not read a pull request that is unchanged since its mapping was written' do
      service.execute(lease_context: lease_context)

      expect(client).not_to have_received(:pull_request)
    end

    context 'when the issues list shows a newer version of the pull request' do
      let(:newer_updated_at) { updated_at + 1.hour }

      before do
        newer_summary = pull_request_summary.merge(updated_at: newer_updated_at)
        newer_pull_request = pull_request_response.merge(title: 'Renamed on GitHub', updated_at: newer_updated_at)
        allow(client).to receive(:pull_request).with('example/connected', 5).and_return(newer_pull_request)
        allow(client).to receive(:each_page)
          .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
          .and_yield(Gitlab::GithubImport::Client::Page.new([newer_summary], nil))
      end

      it 'reads the pull request and updates the merge request' do
        service.execute(lease_context: lease_context)

        expect(client).to have_received(:pull_request).with('example/connected', 5).once
        expect(project.merge_requests.find_by!(iid: 5).title).to eq('Renamed on GitHub')
      end

      it 'advances the pull request mapping only after its reviews are read' do
        pull_request_mapping = Import::Sync::ExternalObject.for_provider(
          repository: repository, kind: :pull_request, provider_object_xid: pull_request_response[:id]
        )
        allow(client).to receive(:pull_request_reviews)
          .and_raise(Gitlab::GithubImport::RateLimitError, 'rate limited provider response')

        expect { service.execute(lease_context: lease_context) }
          .to raise_error(Gitlab::GithubImport::RateLimitError, 'rate limited provider response')
        expect(pull_request_mapping.reload.provider_updated_at).to be_like_time(updated_at)

        allow(client).to receive(:pull_request_reviews).with('example/connected', 5).and_return([review_response])
        service.execute(lease_context: lease_context)

        expect(client).to have_received(:pull_request).with('example/connected', 5).twice
        expect(pull_request_mapping.reload.provider_updated_at).to be_like_time(newer_updated_at)
      end
    end

    context 'when GitHub has a new reply to the imported review comment' do
      let(:reply_response) do
        review_comment_response.merge(id: 406, body: 'Reply', in_reply_to_id: review_comment_response[:id])
      end

      before do
        Gitlab::Cache::Import::Caching.del(
          format(
            Gitlab::GithubImport::Representation::DiffNotes::DiscussionId::DISCUSSION_CACHE_KEY,
            project: 'connected', noteable_id: 5, original_note_id: review_comment_response[:id]
          )
        )
        allow(client).to receive(:each_page)
          .with(:pull_requests_comments, nil, 'example/connected', hash_including(sort: 'created'))
          .and_yield(Gitlab::GithubImport::Client::Page.new([review_comment_response, reply_response], nil))
      end

      it 'adds the reply to the thread of the review comment' do
        service.execute(lease_context: lease_context)

        parent = Import::Sync::ExternalObject.for_provider(
          repository: repository, kind: :review_comment, provider_object_xid: review_comment_response[:id]
        ).note
        reply = Import::Sync::ExternalObject.for_provider(
          repository: repository, kind: :review_comment, provider_object_xid: reply_response[:id]
        ).note

        expect(reply.note).to eq('Reply')
        expect(reply.discussion_id).to eq(parent.discussion_id)
      end
    end

    context 'when the comment was deleted on GitHub' do
      let(:issue_response) { super().merge(comments: 0) }

      before do
        allow(client).to receive(:each_page)
          .with(:issue_comments, nil, 'example/connected', issue_response[:number])
          .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
        allow(client).to receive(:each_page)
          .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
          .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
        allow(client).to receive(:issue_comment)
          .with('example/connected', comment_response[:id])
          .and_raise(Octokit::NotFound)
      end

      it 'removes the note and its mapping' do
        issue = project.issues.find_by!(iid: issue_response[:number])

        expect { service.execute(lease_context: lease_context) }
          .to change { issue.notes.count }.by(-1)
          .and change { Import::Sync::ExternalObject.kind_issue_comment.count }.by(-1)
        expect(work_items_state.reload).to have_attributes(synced_generation: 2, state: 'current')
      end

      context 'when another comment was added in the same window' do
        let(:new_comment) { comment_response.merge(id: 304, body: 'New comment', updated_at: updated_at + 1.hour) }

        before do
          changed_issue = issue_response.merge(comments: 1, updated_at: updated_at + 1.hour)
          allow(client).to receive(:each_page)
            .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
            .and_yield(Gitlab::GithubImport::Client::Page.new([changed_issue, pull_request_summary], nil))
          allow(client).to receive(:each_page)
            .with(:issue_comments, nil, 'example/connected', issue_response[:number])
            .and_yield(Gitlab::GithubImport::Client::Page.new([new_comment], nil))
          allow(client).to receive(:each_page)
            .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
            .and_yield(Gitlab::GithubImport::Client::Page.new([new_comment], nil))
        end

        it 'replaces the deleted note with the new one' do
          issue = project.issues.find_by!(iid: issue_response[:number])

          service.execute(lease_context: lease_context)

          expect(issue.notes.pluck(:note)).to eq(['New comment'])
        end
      end
    end

    context 'when GitHub has a newer version of the issue' do
      let(:newer_updated_at) { updated_at + 1.hour }

      before do
        newer_issue = issue_response.merge(title: 'Renamed on GitHub', updated_at: newer_updated_at)
        allow(client).to receive(:each_page)
          .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
          .and_yield(Gitlab::GithubImport::Client::Page.new([newer_issue], nil))
        allow(client).to receive(:each_page)
          .with(:issue_comments, nil, 'example/connected', issue_response[:number])
          .and_yield(Gitlab::GithubImport::Client::Page.new([comment_response], nil))
      end

      it 'updates the issue and advances its mapping' do
        service.execute(lease_context: lease_context)

        expect(project.issues.find_by!(iid: issue_response[:number]).title).to eq('Renamed on GitHub')
        expect(Import::Sync::ExternalObject.for_provider(repository: repository, kind: :issue, provider_object_xid: 101)
          .provider_updated_at).to be_like_time(newer_updated_at)
      end

      # The reconciler's fence is the lease itself, so the issue is left alone once the lease is gone.
      it 'writes nothing when the lease is lost at the reconciler fence' do
        allow(lease_context).to receive(:verify!)
          .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

        expect { service.execute(lease_context: lease_context) }
          .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

        expect(project.issues.find_by!(iid: issue_response[:number]).title).to eq('Issue')
        expect(work_items_state.reload).to have_attributes(state: 'running', synced_generation: 1)
      end
    end
  end

  context 'when objects have no mapping' do
    let(:project) { repository.project }
    let!(:existing_issue) do
      create(:issue, project: project, iid: issue_response[:number], title: 'Original', imported_from: :github)
    end

    before do
      allow(Import::Sync::Repositories::WorkItems::ReconcileObjectService).to receive(:new).and_call_original
      allow(client).to receive(:each_page)
        .with(:issues, nil, 'example/connected', hash_including(state: 'all'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([issue_response], nil))
      allow(client).to receive(:each_page)
        .with(:issues_comments, nil, 'example/connected', hash_including(sort: 'updated'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
      allow(client).to receive(:each_page)
        .with(:pull_requests_comments, nil, 'example/connected', hash_including(sort: 'created'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
    end

    # D11: an unmapped object that already exists locally is skipped and logged,
    # and the pass still completes instead of freezing the domain.
    it 'skips the existing issue, leaves it unmodified and still reaches the desired generation' do
      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(hash_including(kind: :issue, iid: 4))
      expect(Gitlab::GithubImport::Importer::IssueImporter).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |importer| expect(importer).not_to receive(:execute) }
      end

      expect { service.execute(lease_context: lease_context) }
        .to not_change { Issue.count }.and not_change { Import::Sync::ExternalObject.count }

      expect(existing_issue.reload.title).to eq('Original')
      expect(work_items_state.reload).to have_attributes(synced_generation: 2, desired_generation: 2, state: 'current')
    end
  end

  context 'with label and milestone events', :clean_gitlab_redis_shared_state do
    let_it_be_with_reload(:project) { create(:project) }
    let(:repository) do
      create(
        :import_sync_repository,
        :oauth,
        project: project,
        authority_state: authority_state,
        application_generation: application_generation,
        provider_full_name: 'example/connected'
      )
    end

    let!(:issue) { create(:issue, project: project, iid: 4) }
    let!(:label) { create(:label, project: project, title: 'bug') }
    let(:since) { last_successful_sync_at - described_class::SAFETY_OVERLAP }

    before do
      stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 10)
    end

    def page_url(number)
      "https://api.github.com/repositories/1/issues/events?page=#{number}&per_page=100"
    end

    def newest_event
      label_event(1, since + 30.minutes)
    end

    def oldest_new_event
      label_event(3, since + 10.minutes)
    end

    def boundary_event
      label_event(4, since - 1.minute)
    end

    def first_page
      unknown_issue_event = label_event(2, since + 20.minutes, issue_number: 99)

      Gitlab::GithubImport::Client::Page.new([newest_event, unknown_issue_event], nil, page_url(2))
    end

    def events_stub
      allow(client).to receive(:each_page).with(:repository_issue_events, nil, 'example/connected', {})
    end

    def label_event(id, created_at, issue_number: 4)
      {
        id: id,
        event: 'labeled',
        actor: nil,
        label: { name: 'bug', color: 'fc2929' },
        issue: { number: issue_number, pull_request: nil },
        created_at: created_at.utc.iso8601
      }
    end

    def label_event_times
      issue.resource_label_events.order(:created_at).pluck(:created_at)
    end

    it 'reads pages only until the first event older than the pass window' do
      events_stub
        .and_yield(first_page)
        .and_yield(Gitlab::GithubImport::Client::Page.new([oldest_new_event, boundary_event], page_url(2),
          page_url(3)))
        .and_yield(Gitlab::GithubImport::Client::Page.new([label_event(5, since - 10.minutes)], page_url(3), nil))

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)

      expect(label_event_times).to eq(
        [boundary_event, oldest_new_event, newest_event].map { |event| Time.zone.parse(event[:created_at]) }
      )
      expect(issue.resource_label_events).to all(have_attributes(label_id: label.id, action: 'add'))
    end

    it 'creates each event once when the pass runs twice' do
      events_stub.and_yield(Gitlab::GithubImport::Client::Page.new([newest_event, oldest_new_event], nil))

      service.execute(lease_context: lease_context)
      work_items_state.reload.update!(desired_generation: 3)
      service.execute(lease_context: lease_context)

      expect(label_event_times.size).to eq(2)
      expect(work_items_state.reload).to have_attributes(synced_generation: 3, state: 'current')
    end

    it 'creates each event once when a pass interrupted mid-page resumes' do
      stub_const("#{described_class}::MAX_PROVIDER_PAGES_PER_INVOCATION", 4)
      events_stub.and_yield(first_page)
      allow(client).to receive(:each_page)
        .with(:repository_issue_events, page_url(2), 'example/connected', {})
        .and_yield(Gitlab::GithubImport::Client::Page.new([oldest_new_event, boundary_event], page_url(2), nil))
      importer_calls = 0
      importer_class = Gitlab::GithubImport::Importer::Events::ChangedLabel
      allow(importer_class).to receive(:new).and_wrap_original do |original, *args|
        importer_calls += 1
        raise StandardError, 'interrupted' if importer_calls == 3

        original.call(*args)
      end

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: [], follow_up: true)
      expect(Gitlab::Json::SafeParser.parse(work_items_state.reload.cursor))
        .to include('phase' => 'events', 'page_url' => page_url(2))

      expect { service.execute(lease_context: lease_context) }.to raise_error(StandardError, 'interrupted')
      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)

      expect(label_event_times.size).to eq(3)
    end

    it 'ends the phase when GitHub refuses a page beyond the reachable history' do
      allow(client).to receive(:each_page).with(:repository_issue_events, nil, 'example/connected', {}) do |*, &block|
        block.call(first_page)
        raise Octokit::UnprocessableEntity
      end
      allow(Gitlab::GithubImport::Logger).to receive(:warn)
      allow(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(service.execute(lease_context: lease_context)).to eq(applied_domains: %w[work_items], follow_up: false)

      expect(label_event_times.size).to eq(1)
      expect(Gitlab::GithubImport::Logger).to have_received(:warn).with(
        hash_including(message: 'GitHub issue events beyond the reachable history were not read')
      )
      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(
        an_instance_of(Octokit::UnprocessableEntity), import_sync_repository_id: repository.id, project_id: project.id
      )
    end

    it 'fails the pass when applying an event gets a 422 from GitHub' do
      events_stub.and_yield(first_page)
      allow(Gitlab::GithubImport::Importer::Events::ChangedLabel).to receive(:new).and_raise(Octokit::UnprocessableEntity)

      expect { service.execute(lease_context: lease_context) }.to raise_error(Octokit::UnprocessableEntity)

      expect(work_items_state.reload.synced_generation).to eq(1)
    end
  end
end
