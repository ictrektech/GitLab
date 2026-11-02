# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::ContextService, feature_category: :knowledge_graph do
  include ProjectForksHelper

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, developers: [user]) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:reviewer) { create(:user) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:group_work_item) { create(:work_item, :epic, namespace: group) }
  let_it_be(:repo_project) { create(:project, :repository, group: group) }
  let_it_be(:diff_merge_request) do
    create(:merge_request_with_diffs, source_project: repo_project, target_project: repo_project)
  end

  let(:token) { "MergeRequest[#{merge_request.id}]" }
  let(:access_token) { nil }

  def granular_pat(container, *names)
    permissions = names.map { |name| Authz::PermissionGroups::Assignable.for_permission(name).first.name }
    create(:granular_pat, user: user, boundary: Authz::Boundary.for(container), permissions: permissions)
  end

  def entity_for(token)
    described_class.new(
      user, token, expand: false, format: :raw, request_context: nil, env: {}, access_token: access_token
    ).execute[:entities].first
  end

  subject(:entity) { entity_for(token) }

  before do
    stub_licensed_features(epics: true)
    create(:merge_request_reviewer, merge_request: merge_request, reviewer: reviewer)
  end

  it 'only supports types known to the redaction layer' do
    supported = Analytics::Orbit::ContextToken::REDACTION_TYPES.values.map(&:to_s)

    expect(Authz::RedactionService.supported_types).to include(*supported)
  end

  describe 'container lookup' do
    context 'with a group path and a merge request sigil' do
      let(:token) { "#{group.full_path}!1" }

      it 'is not found because groups hold no merge requests' do
        expect(entity).to include(found: false, error: { code: 'not_found' })
      end
    end

    context 'with a merge request URL under /groups/' do
      let(:token) { "#{Gitlab.config.gitlab.url}/groups/#{group.full_path}/-/merge_requests/1" }

      it 'is not found because groups hold no merge requests' do
        expect(entity).to include(found: false, error: { code: 'not_found' })
      end
    end

    context 'with a group URL' do
      let(:token) { "#{Gitlab.config.gitlab.url}/groups/#{group.full_path}/-/work_items/#{group_work_item.iid}" }

      it 'finds the group-level work item' do
        expect(entity).to include(found: true, id: group_work_item.id.to_s)
      end
    end

    context 'with a project path in a group URL' do
      let(:token) { "#{Gitlab.config.gitlab.url}/groups/#{project.full_path}/-/work_items/1" }

      it 'is not found' do
        expect(entity).to include(found: false, error: { code: 'not_found' })
      end
    end
  end

  describe 'user summaries' do
    it 'lists readable reviewers' do
      expect(entity[:summary][:reviewers]).to contain_exactly(hash_including(id: reviewer.id))
    end

    it 'drops users the current user cannot read' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_user, reviewer).and_return(false)

      expect(entity[:summary][:reviewers]).to be_empty
    end
  end

  describe 'linked work items' do
    let_it_be(:issue) { create(:issue, project: project) }

    before do
      create(:merge_request_issue, merge_request: merge_request, issue: issue)
    end

    it 'links a project work item with its project path' do
      expect(entity[:summary][:linked_issues])
        .to contain_exactly(hash_including(token: "WorkItem[#{issue.id}]", project_path: project.full_path))
    end

    describe 'container queries' do
      let(:options) { { expand: false, format: :raw, request_context: nil, env: {} } }

      def container_query_count(request_token)
        recorder = ActiveRecord::QueryRecorder.new do
          described_class.new(user, request_token, **options).execute
        end

        recorder.log.count { |sql| sql.match?(/FROM "(projects|namespaces|routes)"/) }
      end

      it 'does not grow with the number of linked work items' do
        control = container_query_count(token)

        create_list(:issue, 3, project: project).each do |linked|
          create(:merge_request_issue, merge_request: merge_request, issue: linked)
        end

        expect(container_query_count(token)).to be <= control
      end

      it 'does not grow with the number of linked merge requests' do
        work_item_token = "WorkItem[#{issue.id}]"
        control = container_query_count(work_item_token)

        3.times do |index|
          linked = create(:merge_request, source_project: project, target_project: project,
            source_branch: "linked-#{index}")
          create(:merge_request_issue, merge_request: linked, issue: issue)
        end

        expect(container_query_count(work_item_token)).to be <= control
      end
    end

    context 'when the linked work item is group-level' do
      before do
        create(:merge_request_issue, merge_request: merge_request, issue: group_work_item)
      end

      it 'has a null project path' do
        expect(entity[:summary][:linked_issues])
          .to include(hash_including(token: "WorkItem[#{group_work_item.id}]", project_path: nil))
      end
    end
  end

  describe 'job tokens' do
    let_it_be(:pipeline) { create(:ci_pipeline, project: project, merge_request: merge_request) }
    let_it_be(:job) { create(:ci_build, :failed, pipeline: pipeline, project: project, name: 'rspec') }

    let(:token) { "Job[#{job.id}]" }

    it 'summarizes the job with its pipeline and merge request', :aggregate_failures do
      expect(entity).to include(found: true, type: 'Job', id: job.id.to_s)
      expect(entity[:summary]).to include(
        name: 'rspec', status: 'failed', pipeline_id: pipeline.id, project_path: project.full_path,
        merge_request: hash_including(token: "MergeRequest[#{merge_request.id}]")
      )
    end

    it 'is not found for a job id that does not exist', :aggregate_failures do
      missing_id = job.id + 1000

      expect(entity_for("Job[#{missing_id}]")).to include(found: false)
      expect(entity_for("#{Gitlab.config.gitlab.url}/#{project.full_path}/-/jobs/#{missing_id}"))
        .to include(found: false)
    end

    it 'has no failure reason for a job that has not failed' do
      running = create(:ci_build, :running, pipeline: pipeline, project: project)

      expect(entity_for("Job[#{running.id}]")[:summary]).to include(status: 'running', failure_reason: nil)
    end

    it 'summarizes a job without a stage or merge request', :aggregate_failures do
      other_pipeline = create(:ci_pipeline, project: project)
      bare = create(:ci_build, :failed, pipeline: other_pipeline, project: project)
      allow_next_found_instance_of(Ci::Build) { |build| allow(build).to receive(:ci_stage).and_return(nil) }

      expect(entity_for("Job[#{bare.id}]")[:summary])
        .to include(stage: nil, pipeline_id: other_pipeline.id, merge_request: nil)
    end

    it 'is not found for a user who cannot read the job' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_build, job).and_return(false)

      expect(entity).to include(found: false, error: { code: 'not_found' })
    end

    it 'resolves a job URL only under the job project', :aggregate_failures do
      url = ->(path) { "#{Gitlab.config.gitlab.url}/#{path}/-/jobs/#{job.id}" }

      expect(entity_for(url.call(project.full_path))).to include(found: true)
      expect(entity_for(url.call(repo_project.full_path))).to include(found: false, error: { code: 'not_found' })
    end

    it 'tracks a job failure error and leaves its fields out', :aggregate_failures do
      allow_next_instance_of(Analytics::Orbit::JobFailure) do |failure|
        allow(failure).to receive(:execute).and_raise(StandardError)
      end
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(StandardError), job_id: job.id)

      expect(entity[:summary]).to include(name: 'rspec').and exclude(:log, :failed_tests)
    end

    it 'names the lists that the job failure cut' do
      allow_next_instance_of(Analytics::Orbit::JobFailure) do |failure|
        allow(failure).to receive(:execute).and_return(failed_tests: [], truncated: [:failed_tests])
      end

      expect(entity[:summary][:truncated]).to eq([:failed_tests])
    end

    context 'with a fine-grained token' do
      using RSpec::Parameterized::TableSyntax

      let(:access_token) { granular_pat(project, *grants) }

      context 'without read_job' do
        let(:grants) { %i[read_pipeline] }

        it 'is not found' do
          expect(entity).to include(found: false)
        end
      end

      where(:grants, :read_tests) do
        %i[read_job] | false
        %i[read_job read_pipeline] | true
      end

      with_them do
        it 'reads the test report only with read_pipeline' do
          expect(Analytics::Orbit::JobFailure).to receive(:new)
            .with(job, user, read_log: true, read_tests: read_tests).and_call_original

          expect(entity).to include(found: true)
        end
      end
    end
  end

  describe 'failed jobs' do
    let(:token) { "MergeRequest[#{diff_merge_request.id}]" }

    before_all do
      pipeline = create(:ci_pipeline, :failed, project: repo_project, sha: diff_merge_request.diff_head_sha,
        ref: diff_merge_request.source_branch)
      create(:ci_build, :failed, :allowed_to_fail, pipeline: pipeline, project: repo_project)
      create_list(:ci_build, 2, :failed, pipeline: pipeline, project: repo_project)
      MergeRequest.find(diff_merge_request.id).update!(head_pipeline: pipeline)
    end

    it 'lists blocking failures first and names the cut', :aggregate_failures do
      stub_const("#{described_class}::MAX_FAILED_JOBS", 2)

      expect(entity[:summary][:failed_jobs].pluck(:allow_failure)).to match_array([false, false])
      expect(entity[:summary][:truncated]).to include(:failed_jobs)
    end

    it 'leaves the jobs out when the user cannot read the pipeline jobs' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_build, an_instance_of(Ci::Pipeline)).and_return(false)

      expect(entity[:summary][:failed_jobs]).to be_nil
    end

    it 'traces only the first jobs and leaves a missing stage out', :aggregate_failures do
      stub_const("#{described_class}::MAX_TRACED_JOBS", 1)
      allow_next_found_instance_of(Ci::Build) { |build| allow(build).to receive(:ci_stage).and_return(nil) }
      allow(Analytics::Orbit::JobFailure).to receive(:new).and_call_original

      expect(entity[:summary][:failed_jobs]).to all(exclude(:stage))
      expect(Analytics::Orbit::JobFailure).to have_received(:new).once
    end

    context 'with a fine-grained token without read_job' do
      let(:access_token) { granular_pat(repo_project, :read_merge_request, :read_pipeline) }

      it 'lists the jobs without their logs' do
        expect(Analytics::Orbit::JobFailure).to receive(:new)
          .with(anything, user, read_log: false, read_tests: true).at_least(:once).and_call_original

        expect(entity[:summary][:failed_jobs]).to be_present
      end
    end
  end

  describe 'changed files' do
    let(:diff) do
      create(:merge_request_with_diffs, source_project: repo_project, target_project: repo_project,
        source_branch: 'fix', target_branch: 'master').merge_request_diff
    end

    let(:token) { "MergeRequest[#{diff.merge_request_id}]" }

    it 'reads an externally stored diff without caching a copy', :aggregate_failures do
      stub_external_diffs_setting(enabled: true)
      MergeRequests::MigrateExternalDiffsService.new(diff).execute

      expect(diff).to be_stored_externally
      expect(entity[:summary][:changed_files]).to include(a_hash_including(lines: be_present))
      expect(Dir.exist?(diff.send(:external_diff_cache_dir))).to be(false)
    end

    it 'lists each file with its status and changed line ranges, up to the cap', :aggregate_failures do
      expect(entity[:summary][:changed_files]).to contain_exactly(
        a_hash_including(path: '.testdir/README.md', status: 'A', lines: be_present),
        { path: 'files/js/application.js', status: 'M', lines: %w[27 30-33] }
      )

      stub_const("#{described_class}::MAX_CHANGED_FILES", 1)
      summary = entity_for(token)[:summary]
      expect(summary[:changed_files].size).to eq(1)
      expect(summary[:truncated]).to include(:changed_files)
    end

    it 'folds line ranges beyond the cap into a count', :aggregate_failures do
      stub_const("#{described_class}::MAX_LINE_RANGES", 1)

      expect(entity[:summary][:changed_files]).to include(
        a_hash_including(path: 'files/js/application.js', lines: ['27', '+1 more'])
      )
    end

    it 'lists no files for a merge request without a diff' do
      allow_next_found_instance_of(MergeRequest) { |mr| allow(mr).to receive(:merge_request_diff).and_return(nil) }

      expect(entity[:summary][:changed_files]).to be_nil
    end

    it 'leaves the lines out of only the file whose diff cannot be parsed', :aggregate_failures do
      failing = instance_double(Gitlab::Diff::Parser)
      allow(failing).to receive(:parse).and_raise(ArgumentError)
      allow(Gitlab::Diff::Parser).to receive(:new).and_return(failing, Gitlab::Diff::Parser.new)
      expect(Gitlab::ErrorTracking).to receive(:track_exception).once

      files = entity[:summary][:changed_files]
      expect(files.first).to include(path: '.testdir/README.md').and exclude(:lines)
      expect(files.second).to include(path: 'files/js/application.js', lines: be_present)
    end

    it 'tracks a diff read error once and lists the files without lines', :aggregate_failures do
      allow_next_found_instance_of(MergeRequestDiffFile) do |file|
        allow(file).to receive(:diff).and_raise(Errno::ENOENT)
      end
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .once.with(an_instance_of(Errno::ENOENT), merge_request_diff_id: diff.id)

      expect(entity[:summary][:changed_files]).to be_present.and all(exclude(:lines))
    end

    it 'lists the files without lines when the diff cannot be read', :aggregate_failures do
      allow_next_found_instance_of(MergeRequestDiff) do |instance|
        allow(instance).to receive(:opening_external_diff).and_raise(Errno::ENOENT)
      end
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(Errno::ENOENT), merge_request_diff_id: diff.id)

      expect(entity[:summary][:changed_files]).to be_present.and all(include(:path, :status).and(exclude(:lines)))
    end
  end

  describe 'discussions' do
    let(:token) { "MergeRequest[#{diff_merge_request.id}]" }

    before_all do
      args = { noteable: diff_merge_request, project: repo_project }
      create(:diff_note_on_merge_request, note: 'text', **args)
      create(:image_diff_note_on_merge_request, note: 'image', **args)
      create(:diff_note_on_merge_request, note: 'file', **args,
        position: build(:file_diff_position, file: 'files/ruby/popen.rb', diff_refs: diff_merge_request.diff_refs))
    end

    it 'gives a line only for text diff positions' do
      expect(entity[:summary][:discussions]).to contain_exactly(
        a_hash_including(body: 'text', path: 'files/ruby/popen.rb', line: 14),
        a_hash_including(body: 'image', path: 'files/images/any_image.png').and(exclude(:line)),
        a_hash_including(body: 'file', path: 'files/ruby/popen.rb').and(exclude(:line))
      )
    end

    it 'lists a note whose author is gone', :aggregate_failures do
      note = create(:note, note: 'orphan', noteable: diff_merge_request, project: repo_project)
      note.update_column(:author_id, nil)

      expect(entity[:summary][:discussions]).to include(a_hash_including(body: 'orphan', author: nil))
    end

    it 'hides internal notes from a user who cannot read them' do
      public_merge_request = create(:merge_request, source_project: create(:project, :public))
      args = { noteable: public_merge_request, project: public_merge_request.project }
      create(:note, note: 'public', **args)
      create(:note, :confidential, note: 'internal', **args)

      expect(entity_for("MergeRequest[#{public_merge_request.id}]")[:summary][:discussions].pluck(:body))
        .to eq(['public'])
    end

    it 'keeps the newest notes, oldest first, and marks the cut' do
      stub_const("#{described_class}::MAX_NOTES", 2)

      expect(entity[:summary][:discussions].pluck(:body)).to eq(%w[image file])
      expect(entity[:summary][:truncated]).to include(:discussions)
    end
  end

  describe 'granular token checks' do
    let(:permissions) do
      %i[read_orbit read_merge_request read_pipeline].map do |name|
        Authz::PermissionGroups::Assignable.for_permission(name).first.name
      end
    end

    let(:access_token) do
      create(:granular_pat, user: user, boundary: Authz::Boundary.for(project), permissions: permissions)
    end

    it 'authorizes each permission and container once' do
      expect(Authz::Tokens::AuthorizeGranularScopesService).to receive(:new).at_most(4).times.and_call_original

      expect(entity).to include(found: true)
    end

    it 'checks download_code before listing changed files and the discussion permission before notes' do
      allow(Authz::Tokens::AuthorizeGranularScopesService).to receive(:new).and_call_original

      expect(entity[:summary][:changed_files]).to be_nil
      expect(Authz::Tokens::AuthorizeGranularScopesService)
        .to have_received(:new).with(hash_including(permissions: :download_code))
      expect(Authz::Tokens::AuthorizeGranularScopesService)
        .to have_received(:new).with(hash_including(permissions: :read_merge_request_discussion))
    end

    it 'leaves discussions out when the token lacks the discussion permission' do
      allow_next_instance_of(described_class) do |service|
        allow(service).to receive(:granular_scope_allowed?).and_call_original
        allow(service).to receive(:granular_scope_allowed?).with(:read_merge_request_discussion, anything)
          .and_return(false)
      end

      expect(entity[:summary][:discussions]).to be_nil
    end

    context 'with work items' do
      using RSpec::Parameterized::TableSyntax

      let(:access_token) { granular_pat(group, :read_work_item) }
      let(:group_issue) { create(:work_item, :group_level, namespace: group) }
      let(:project_issue) { create(:work_item, project: project) }

      where(:record, :permission) do
        :group_work_item | :read_epic_discussion
        :group_issue | :read_issue_discussion
        :project_issue | :read_issue_discussion
      end

      with_them do
        let(:token) { "WorkItem[#{public_send(record).id}]" }

        it 'checks the discussion permission of the work item type' do
          allow(Authz::Tokens::AuthorizeGranularScopesService).to receive(:new).and_call_original

          expect(entity).to include(found: true)
          expect(Authz::Tokens::AuthorizeGranularScopesService)
            .to have_received(:new).with(hash_including(permissions: permission))
        end
      end
    end

    it 'is not found when the token lacks the permission' do
      token_without_grants = create(:granular_pat, user: user, boundary: Authz::Boundary.for(group),
        permissions: [Authz::PermissionGroups::Assignable.for_permission(:read_orbit).first.name])

      result = described_class.new(
        user, token, expand: false, format: :raw, request_context: nil, env: {}, access_token: token_without_grants
      ).execute[:entities].first

      expect(result).to include(found: false)
    end
  end

  describe 'pipeline tokens' do
    let_it_be(:pipeline) { create(:ci_pipeline, :failed, project: project, merge_request: merge_request) }
    let_it_be(:failed_job) { create(:ci_build, :failed, pipeline: pipeline, project: project, name: 'rspec') }

    let(:token) { "Pipeline[#{pipeline.id}]" }

    it 'summarizes the pipeline with its merge request and failed jobs', :aggregate_failures do
      expect(entity).to include(
        found: true, type: 'Pipeline', id: pipeline.id.to_s, resolved_token: "Pipeline[#{pipeline.id}]"
      )
      expect(entity[:summary]).to include(
        status: 'failed', ref: pipeline.ref, project_path: project.full_path,
        merge_request: hash_including(token: "MergeRequest[#{merge_request.id}]"),
        failed_jobs: [hash_including(name: 'rspec')]
      )
      expect(entity[:summary][:merge_request]).not_to have_key(:relation)
    end

    it 'resolves a GID and a pipeline URL only under the pipeline project', :aggregate_failures do
      url = ->(path) { "#{Gitlab.config.gitlab.url}/#{path}/-/pipelines/#{pipeline.id}" }

      expect(entity_for("gid://gitlab/Ci::Pipeline/#{pipeline.id}")).to include(found: true)
      expect(entity_for(url.call(project.full_path))).to include(found: true)
      expect(entity_for(url.call(repo_project.full_path))).to include(found: false, error: { code: 'not_found' })
    end

    it 'is not found for a user who cannot read the pipeline' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_pipeline, pipeline).and_return(false)

      expect(entity).to include(found: false, error: { code: 'not_found' })
    end

    it 'is not found when the pipeline has no project' do
      allow_next_found_instance_of(Ci::Pipeline) { |found| allow(found).to receive(:project).and_return(nil) }

      expect(entity).to include(found: false, error: { code: 'not_found' })
    end

    it 'leaves out a merge request the user cannot read' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_merge_request, merge_request).and_return(false)

      expect(entity[:summary]).to include(merge_request: nil)
    end

    it 'lists the latest jobs and leaves out retried ones', :aggregate_failures do
      create(:ci_build, :success, pipeline: pipeline, project: project, name: 'build')
      create(:ci_build, :failed, :retried, pipeline: pipeline, project: project, name: 'rspec')

      jobs = entity[:summary][:jobs]

      expect(jobs.pluck(:name).tally).to eq('build' => 1, 'rspec' => 1)
      expect(jobs.find { |job| job[:name] == 'rspec' }).to include(status: 'failed', allow_failure: false)
    end

    it 'marks a job that is allowed to fail' do
      create(:ci_build, :failed, :allowed_to_fail, pipeline: pipeline, project: project, name: 'optional')

      expect(entity[:summary][:jobs].find { |job| job[:name] == 'optional' }).to include(allow_failure: true)
    end

    it 'leaves the stage out of a job without one' do
      allow_next_found_instance_of(Ci::Build) { |build| allow(build).to receive(:ci_stage).and_return(nil) }

      expect(entity[:summary][:jobs]).to all(include(stage: nil))
    end

    it 'does not run more queries as the pipeline gets more jobs' do
      entity_for(token)
      control = ActiveRecord::QueryRecorder.new { entity_for(token) }

      create_list(:ci_build, 3, :success, pipeline: pipeline, project: project)

      expect { entity_for(token) }.not_to exceed_query_limit(control)
    end

    it 'caps the job list' do
      stub_const("#{described_class}::MAX_PIPELINE_JOBS", 1)
      create(:ci_build, :success, pipeline: pipeline, project: project, name: 'build')

      expect(entity[:summary]).to include(jobs: [hash_including(name: 'rspec')], truncated: [:jobs])
    end

    it 'leaves out jobs when the user cannot read them', :aggregate_failures do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_build, pipeline).and_return(false)

      expect(entity[:summary]).to include(jobs: nil, failed_jobs: nil)
    end

    context 'with a fine-grained token without read_pipeline' do
      let(:access_token) { granular_pat(project, :read_job) }

      it 'is not found' do
        expect(entity).to include(found: false, error: { code: 'not_found' })
      end
    end
  end

  describe 'branch and commit tokens' do
    let_it_be(:branch) { 'improve/awesome' }
    let_it_be(:branch_merge_request) do
      create(:merge_request, source_project: repo_project, target_project: repo_project, source_branch: branch,
        target_branch: 'master')
    end

    let_it_be(:branch_sha) { repo_project.commit(branch).sha }
    let_it_be(:branch_pipeline) do
      create(:ci_pipeline, :failed, project: repo_project, ref: branch, sha: branch_sha)
    end

    let_it_be(:branch_job) do
      create(:ci_build, :failed, pipeline: branch_pipeline, project: repo_project, name: 'lint')
    end

    let_it_be(:skipped_pipeline) { create(:ci_pipeline, :skipped, project: repo_project, ref: branch, sha: branch_sha) }

    let(:token) { "#{repo_project.full_path}@#{branch}" }

    it 'summarizes the branch with its merge request and latest pipeline that ran', :aggregate_failures do
      expect(entity).to include(
        found: true, type: 'Branch', id: branch, resolved_token: "#{repo_project.full_path}@#{branch}"
      )
      expect(entity[:summary]).to include(
        name: branch, sha: branch_sha, default_branch: false, project_path: repo_project.full_path,
        merge_request: hash_including(token: "MergeRequest[#{branch_merge_request.id}]"),
        pipeline_id: branch_pipeline.id, pipeline_status: 'failed', failed_jobs: [hash_including(name: 'lint')]
      )
    end

    it 'prefers the open merge request from the branch' do
      create(:merge_request, :closed, source_project: repo_project, target_project: repo_project,
        source_branch: branch, target_branch: 'feature', updated_at: 1.minute.from_now)

      expect(entity[:summary][:merge_request]).to include(token: "MergeRequest[#{branch_merge_request.id}]")
    end

    it 'resolves a commit SHA that is not a branch name', :aggregate_failures do
      commit_entity = entity_for("#{repo_project.full_path}@#{branch_sha[0, 12]}")

      expect(commit_entity).to include(
        found: true, type: 'Commit', id: branch_sha, resolved_token: "#{repo_project.full_path}@#{branch_sha}"
      )
      expect(commit_entity[:summary]).to include(
        sha: branch_sha, title: repo_project.commit(branch_sha).title, pipeline_id: branch_pipeline.id,
        description: repo_project.commit(branch_sha).description.presence
      )
      expect(entity_for("#{Gitlab.config.gitlab.url}/#{repo_project.full_path}/-/commit/#{branch_sha}"))
        .to include(found: true, type: 'Commit')
    end

    it 'lists the files the commit changed with their changed lines', :aggregate_failures do
      diffs = repo_project.commit(branch_sha).raw_diffs.to_a
      edited = diffs.reject(&:deleted_file).select { |diff| diff.diff.lines.any? { |line| line.start_with?('+', '-') } }

      files = entity_for("#{repo_project.full_path}@#{branch_sha}")[:summary][:changed_files]

      expect(files.pluck(:path)).to match_array(diffs.map(&:new_path))
      expect(files).to all(include(:status))
      expect(edited).not_to be_empty
      expect(files.select { |file| edited.map(&:new_path).include?(file[:path]) })
        .to all(include(lines: be_present))
    end

    it 'names changed files as cut when the commit changed more files than the cap' do
      stub_const("#{described_class}::MAX_CHANGED_FILES", 0)

      expect(entity_for("#{repo_project.full_path}@#{branch_sha}")[:summary]).to include(
        changed_files: [], truncated: [:changed_files]
      )
    end

    it 'tracks a diff error and leaves changed files out' do
      allow_next_instance_of(Commit) { |commit| allow(commit).to receive(:raw_diffs).and_raise(StandardError) }
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(StandardError),
        commit_sha: branch_sha)

      expect(entity_for("#{repo_project.full_path}@#{branch_sha}")[:summary]).to include(changed_files: nil)
    end

    it 'lists only the merge requests containing the commit that the user can read', :aggregate_failures do
      sha = diff_merge_request.commits.first.sha
      token = "#{repo_project.full_path}@#{sha}"

      expect(entity_for(token)[:summary][:merge_requests])
        .to contain_exactly(hash_including(token: "MergeRequest[#{diff_merge_request.id}]"))

      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_merge_request, diff_merge_request).and_return(false)

      expect(entity_for(token)[:summary][:merge_requests]).to be_empty
    end

    it 'summarizes a branch without a pipeline' do
      expect(entity_for("#{repo_project.full_path}@feature")[:summary])
        .to include(pipeline_id: nil, pipeline_status: nil, failed_jobs: nil)
    end

    it 'summarizes a branch whose target cannot be resolved', :aggregate_failures do
      git_branch = instance_double(Gitlab::Git::Branch, name: branch, dereferenced_target: nil)
      allow_next_instance_of(Repository) do |repository|
        allow(repository).to receive(:find_branch).and_return(git_branch)
      end

      expect(entity[:summary]).to include(sha: nil, pipeline_id: nil, failed_jobs: nil)
    end

    it 'leaves out the changed files of a commit without read_commit_diff' do
      service = described_class.new(
        user, "#{repo_project.full_path}@#{branch_sha}", expand: false, format: :raw, request_context: nil, env: {}
      )
      allow(service).to receive(:granular_scope_allowed?).and_call_original
      allow(service).to receive(:granular_scope_allowed?).with(:read_commit_diff, anything).and_return(false)

      expect(service.execute[:entities].first[:summary]).to include(changed_files: nil)
    end

    it 'leaves out the authored date of a commit without one' do
      allow_next_instance_of(Commit) { |commit| allow(commit).to receive(:authored_date).and_return(nil) }

      expect(entity_for("#{repo_project.full_path}@#{branch_sha}")[:summary]).to include(authored_date: nil)
    end

    it 'names changed files as cut when the diff overflows' do
      diffs = instance_double(Gitlab::Git::DiffCollection, to_a: [], overflow?: true)
      allow_next_instance_of(Commit) { |commit| allow(commit).to receive(:raw_diffs).and_return(diffs) }

      expect(entity_for("#{repo_project.full_path}@#{branch_sha}")[:summary]).to include(
        changed_files: [], truncated: [:changed_files]
      )
    end

    [Gitlab::Git::Repository::NoRepository, Gitlab::Git::CommandError].each do |error|
      it "is not found for a branch or commit when the repository raises #{error}", :aggregate_failures do
        allow_next_instance_of(Repository) do |repository|
          allow(repository).to receive(:find_branch).and_raise(error)
          allow(repository).to receive(:commit).and_raise(error)
        end

        expect(entity).to include(found: false, error: { code: 'not_found' })
        expect(entity_for("#{repo_project.full_path}@#{branch_sha}"))
          .to include(found: false, error: { code: 'not_found' })
      end
    end

    it 'is not found for an unknown branch or a name that is not a SHA', :aggregate_failures do
      not_found = { found: false, error: { code: 'not_found' } }

      expect(entity_for("#{repo_project.full_path}@missing-branch")).to include(not_found)
      expect(entity_for("#{repo_project.full_path}@#{'0' * 40}")).to include(not_found)
    end

    it 'does not touch the repository of a project whose code is for members only', :aggregate_failures do
      members_only = create(:project, :repository, :public, repository_access_level: ProjectFeature::PRIVATE)
      sha = members_only.commit.sha
      expect(Gitlab::GitalyClient).not_to receive(:call)

      expect(entity_for("#{members_only.full_path}@master")).to include(found: false, error: { code: 'not_found' })
      expect(entity_for("#{members_only.full_path}@#{sha}")).to include(found: false, error: { code: 'not_found' })
    end

    it 'ignores fork merge requests whose source branch has the same name' do
      fork = fork_project(repo_project)
      create(:merge_request, source_project: fork, target_project: repo_project, source_branch: branch,
        target_branch: 'master', updated_at: 1.minute.from_now)

      expect(entity[:summary][:merge_request]).to include(token: "MergeRequest[#{branch_merge_request.id}]")
    end

    it 'leaves out the merge requests of a commit without read_commit_merge_request' do
      service = described_class.new(
        user, "#{repo_project.full_path}@#{branch_sha}", expand: false, format: :raw, request_context: nil, env: {}
      )
      allow(service).to receive(:granular_scope_allowed?).and_call_original
      allow(service).to receive(:granular_scope_allowed?).with(:read_commit_merge_request, anything).and_return(false)

      expect(service.execute[:entities].first[:summary]).to include(merge_requests: nil)
    end

    it 'is not found in a private project the user is not a member of' do
      other = create(:project, :repository, :private)

      expect(entity_for("#{other.full_path}@master")).to include(found: false, error: { code: 'not_found' })
    end

    context 'with a fine-grained token' do
      let(:access_token) { granular_pat(repo_project, *grants) }

      context 'without read_branch' do
        let(:grants) { %i[read_commit] }

        it 'is not found for a branch and does not look it up' do
          expect(Gitlab::GitalyClient).not_to receive(:call)

          expect(entity).to include(found: false, error: { code: 'not_found' })
        end
      end

      context 'without read_commit' do
        let(:grants) { %i[read_branch] }

        it 'is not found for a commit' do
          expect(entity_for("#{repo_project.full_path}@#{branch_sha}")).to include(found: false)
        end
      end

      context 'with read_branch only' do
        let(:grants) { %i[read_branch] }

        it 'finds the branch and leaves out what the token cannot read', :aggregate_failures do
          expect(entity).to include(found: true, type: 'Branch')
          expect(entity[:summary]).to include(merge_request: nil, pipeline_id: nil, failed_jobs: nil)
        end
      end
    end
  end
end
