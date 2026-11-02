# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AgenticAnalyzer, feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }

  def create_scanned_pipeline(source: :duo_workflow, scan_type: :sast, partial: false, ref: 'refs/workloads/abc123')
    pipeline = create(:ci_pipeline, :success, project: project, ref: ref, sha: sha, source: source)
    build = create(:ci_build, :success, pipeline: pipeline, project: project)
    scan = create(:security_scan, scan_type: scan_type, status: :succeeded, build: build, latest: true)
    create(:vulnerabilities_partial_scan, scan: scan) if partial
    pipeline
  end

  describe '.enabled?' do
    let_it_be(:top_level_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: top_level_group) }
    let_it_be(:group_project) { create(:project, group: subgroup) }

    it 'is enabled for the projects of the top-level group the flag is enabled for' do
      stub_feature_flags(agentic_analyzer_security_ingestion: top_level_group)

      expect(described_class.enabled?(group_project)).to be(true)
    end

    it 'is disabled for the projects of another top-level group' do
      stub_feature_flags(agentic_analyzer_security_ingestion: create(:group))

      expect(described_class.enabled?(group_project)).to be(false)
    end

    it 'is disabled when the flag is enabled only for the project' do
      stub_feature_flags(agentic_analyzer_security_ingestion: group_project)

      expect(described_class.enabled?(group_project)).to be(false)
    end
  end

  describe '.default_branch_scan?' do
    subject(:default_branch_scan?) { described_class.default_branch_scan?(pipeline) }

    let(:default_sha) { project.commit(project.default_branch).id }

    context 'when pipeline is a workload with SHA matching default branch HEAD' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      it { is_expected.to be true }
    end

    context 'when pipeline is not a workload' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'feature-branch', sha: default_sha)
      end

      it { is_expected.to be false }
    end

    context 'when the feature flag is disabled' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it { is_expected.to be false }
    end

    context 'when pipeline SHA does not match default branch HEAD' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: 'f' * 40, source: :duo_workflow)
      end

      it { is_expected.to be false }
    end

    context 'when the default branch moved after the scan was dispatched' do
      let(:dispatch_sha) { project.commit(project.default_branch).parent_id }
      let(:source) { :duo_workflow }
      let(:source_branch) { project.default_branch }
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: dispatch_sha, source: source)
      end

      before do
        variables = [{ key: described_class::SOURCE_BRANCH_VARIABLE, value: source_branch, public: true }]
        create(:ci_build, pipeline: pipeline, project: project, yaml_variables: source_branch ? variables : [])
      end

      it 'is still a default-branch scan and logs why', :aggregate_failures do
        allow(Gitlab::AppJsonLogger).to receive(:info)
        expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
          default_branch_scan: true, default_branch_scan_reason: 'default_branch_moved_since_dispatch',
          Labkit::Fields::GL_PIPELINE_ID => pipeline.id))

        expect(default_branch_scan?).to be true
      end

      context 'when a force push rewrote the dispatch SHA off the default branch' do
        let(:dispatch_sha) { project.commit('feature').id }

        it 'is not a default-branch scan and logs why', :aggregate_failures do
          allow(Gitlab::AppJsonLogger).to receive(:info)
          expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
            default_branch_scan: false, default_branch_scan_reason: 'dispatch_sha_not_on_default_branch',
            Labkit::Fields::GL_PIPELINE_ID => pipeline.id))

          expect(default_branch_scan?).to be false
        end
      end

      context 'when the scan was dispatched for a non-default branch' do
        let(:source_branch) { 'feature-branch' }

        it 'is not a default-branch scan and logs why', :aggregate_failures do
          allow(Gitlab::AppJsonLogger).to receive(:info)
          expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
            default_branch_scan: false, default_branch_scan_reason: 'not_dispatched_for_default_branch',
            Labkit::Fields::GL_PIPELINE_ID => pipeline.id))

          expect(default_branch_scan?).to be false
        end
      end

      context 'when the workload has no dispatch branch variable' do
        let(:source_branch) { nil }

        it 'is not a default-branch scan and logs that the branch is unknown', :aggregate_failures do
          allow(Gitlab::AppJsonLogger).to receive(:info)
          expect(Gitlab::AppJsonLogger).to receive(:info).with(hash_including(
            default_branch_scan: false, default_branch_scan_reason: 'dispatch_branch_unknown',
            Labkit::Fields::GL_PIPELINE_ID => pipeline.id))

          expect(default_branch_scan?).to be false
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it { is_expected.to be false }
      end

      context 'when the workload has another source' do
        let(:source) { :dependency_management_security_update }

        it { is_expected.to be false }
      end

      context 'when the pipeline is not a workload' do
        let(:pipeline) { create(:ci_pipeline, project: project, ref: 'feature-branch', sha: dispatch_sha) }

        it 'is not a default-branch scan and does not log' do
          expect(Gitlab::AppJsonLogger).not_to receive(:info)

          expect(default_branch_scan?).to be false
        end
      end
    end

    context 'when the project has no commits' do
      let_it_be(:empty_project) { create(:project) }

      let(:pipeline) do
        create(:ci_pipeline, project: empty_project, ref: 'refs/workloads/abc123', sha: 'a' * 40, source: :duo_workflow)
      end

      it { is_expected.to be false }
    end

    context 'when called multiple times for the same pipeline' do
      let(:pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: default_sha, source: :duo_workflow)
      end

      it 'memoizes the result to avoid duplicate Gitaly calls' do
        allow(pipeline).to receive(:project).and_return(project)

        expect(project).to receive(:commit).once.and_call_original

        Gitlab::SafeRequestStore.ensure_request_store do
          2.times { described_class.default_branch_scan?(pipeline) }
        end
      end
    end
  end

  describe '.pipeline_has_successful_scan?' do
    subject { described_class.pipeline_has_successful_scan?(pipeline, 'sast') }

    let(:pipeline) { create(:ci_pipeline, :success, project: project) }

    def create_scan(scan_pipeline, scan_type: :sast, status: :succeeded)
      build = create(:ci_build, :success, pipeline: scan_pipeline, project: project)
      create(:security_scan, scan_type: scan_type, status: status, build: build, latest: true)
    end

    it { is_expected.to be false }

    context 'with a successful SAST scan and no findings' do
      before do
        create_scan(pipeline)
      end

      it { is_expected.to be true }
    end

    context 'with a successful SAST scan in a child pipeline' do
      before do
        create_scan(create(:ci_pipeline, :success, project: project, child_of: pipeline))
      end

      it { is_expected.to be true }
    end

    context 'with only a failed SAST scan' do
      before do
        create_scan(pipeline, status: :job_failed)
      end

      it { is_expected.to be false }
    end

    context 'with only a successful scan of another type' do
      before do
        create_scan(pipeline, scan_type: :dependency_scanning)
      end

      it { is_expected.to be false }
    end
  end

  describe '.scan_pipeline_ids_for' do
    subject(:scan_pipeline_ids) { described_class.scan_pipeline_ids_for(project, sha) }

    let(:sha) { 'a' * 40 }

    it 'returns duo_workflow pipelines with a succeeded SAST scan at the SHA' do
      pipeline = create_scanned_pipeline

      expect(scan_pipeline_ids).to contain_exactly(pipeline.id)
    end

    it 'returns only the latest of two full runs at the SHA' do
      create_scanned_pipeline
      latest = create_scanned_pipeline

      expect(scan_pipeline_ids).to contain_exactly(latest.id)
    end

    it 'returns the latest full run and the latest partial run' do
      create_scanned_pipeline
      full = create_scanned_pipeline
      create_scanned_pipeline(partial: true)
      partial = create_scanned_pipeline(partial: true)

      expect(scan_pipeline_ids).to contain_exactly(full.id, partial.id)
    end

    it 'excludes other workload sources' do
      create_scanned_pipeline(source: :dependency_management_security_update)

      expect(scan_pipeline_ids).to be_empty
    end

    it 'excludes non-SAST scans' do
      create_scanned_pipeline(scan_type: :dependency_scanning)

      expect(scan_pipeline_ids).to be_empty
    end

    it 'only considers the newest MAX_WORKLOAD_CANDIDATES pipelines at the SHA' do
      stub_const("#{described_class}::MAX_WORKLOAD_CANDIDATES", 1)
      create_scanned_pipeline
      # A newer duo_workflow pipeline without a scan pushes the scanned one out of the candidate window.
      create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/def456', sha: sha, source: :duo_workflow)

      expect(scan_pipeline_ids).to be_empty
    end

    it 'only looks up pipelines in the recent CI partitions' do
      pipeline = create_scanned_pipeline
      allow(Ci::Partition).to receive(:recent_ids).and_return([pipeline.partition_id + 1])

      expect(scan_pipeline_ids).to be_empty
    end

    it 'caches the workload pipeline lookup per request' do
      create_scanned_pipeline

      expect(Ci::Pipeline).to receive(:recent_ids_for_sha_and_source).once.and_call_original

      Gitlab::SafeRequestStore.ensure_request_store do
        2.times { described_class.scan_pipeline_ids_for(project, sha) }
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it 'returns nothing' do
        create_scanned_pipeline

        expect(scan_pipeline_ids).to be_empty
      end
    end
  end

  describe '.scan_pipeline_for' do
    it 'returns the latest duo_workflow pipeline with a succeeded SAST scan at the SHA' do
      sha = 'b' * 40
      pipelines = Array.new(2) do
        pipeline = create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/abc123', sha: sha,
          source: :duo_workflow)
        create(:security_scan, scan_type: :sast, status: :succeeded, latest: true,
          build: create(:ci_build, :success, pipeline: pipeline, project: project))
        pipeline
      end

      expect(described_class.scan_pipeline_for(project, sha)).to eq(pipelines.last)
    end

    it 'skips a newer pipeline whose only agentic scan is of another report type' do
      stub_const("#{described_class}::AGENTIC_REPORT_TYPES", %w[sast secret_detection])
      sha = 'c' * 40
      sast_pipeline, _other_pipeline = %i[sast secret_detection].map do |scan_type|
        pipeline = create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/abc123', sha: sha,
          source: :duo_workflow)
        create(:security_scan, scan_type: scan_type, status: :succeeded, latest: true,
          build: create(:ci_build, :success, pipeline: pipeline, project: project))
        pipeline
      end

      expect(described_class.scan_pipeline_for(project, sha, 'sast')).to eq(sast_pipeline)
    end
  end

  describe '.latest_branch_scan_pipeline_for' do
    subject(:branch_scan_pipeline) { described_class.latest_branch_scan_pipeline_for(project, 'master') }

    let(:branch_head) { project.commit('master') }

    def create_scan_pipeline(
      sha:, partial: false, workflow_definition: Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE)
      pipeline = create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/abc123', sha: sha,
        source: :duo_workflow)
      create(:duo_workflows_workload, workload: create(:ci_workload, pipeline: pipeline),
        workflow: create(:duo_workflows_workflow, project: project, workflow_definition: workflow_definition))
      scan = create(:security_scan, scan_type: :sast, status: :succeeded, latest: true,
        build: create(:ci_build, :success, pipeline: pipeline, project: project))
      create(:vulnerabilities_partial_scan, scan: scan) if partial
      pipeline
    end

    it 'returns the scan of the branch HEAD' do
      pipeline = create_scan_pipeline(sha: branch_head.id)

      expect(branch_scan_pipeline).to eq(pipeline)
    end

    it 'returns the latest scan of an older commit on the branch' do
      pipeline = create_scan_pipeline(sha: branch_head.parent_id)

      expect(branch_scan_pipeline).to eq(pipeline)
    end

    it 'skips partial scans and scans of commits that are not on the branch' do
      pipeline = create_scan_pipeline(sha: branch_head.parent_id)
      create_scan_pipeline(sha: branch_head.id, partial: true)
      create_scan_pipeline(sha: project.commit('feature').id)

      expect(branch_scan_pipeline).to eq(pipeline)
    end

    it 'skips full scans that another flow ran' do
      pipeline = create_scan_pipeline(sha: branch_head.parent_id)
      create_scan_pipeline(sha: branch_head.id, workflow_definition: 'software_development')

      expect(branch_scan_pipeline).to eq(pipeline)
    end

    context 'when newer partial scans precede the full scan' do
      let!(:full_scan_pipeline) { create_scan_pipeline(sha: branch_head.parent_id) }

      before do
        stub_const("#{described_class}::MAX_WORKLOAD_CANDIDATES", 2)
        3.times { create_scan_pipeline(sha: branch_head.id, partial: true) }
      end

      it 'finds an older full scan among newer partial scans in the window' do
        expect(branch_scan_pipeline).to eq(full_scan_pipeline)
      end

      it 'returns nil when the full scan is outside the window' do
        stub_const('::EE::Ci::Pipeline::RECENT_SOURCE_IDS_WINDOW', 3)

        expect(branch_scan_pipeline).to be_nil
      end

      it 'stops after MAX_BRANCH_SCAN_WORKLOADS workload pipelines' do
        stub_const("#{described_class}::MAX_BRANCH_SCAN_WORKLOADS", 3)

        expect(branch_scan_pipeline).to be_nil
      end
    end

    context 'when no full scan is in the window' do
      before do
        stub_const("#{described_class}::MAX_WORKLOAD_CANDIDATES", 1)
      end

      def query_count_after_adding(partial_scans)
        partial_scans.times { create_scan_pipeline(sha: branch_head.id, partial: true) }

        ActiveRecord::QueryRecorder.new(skip_cached: false) do
          expect(described_class.latest_branch_scan_pipeline_for(project, 'master')).to be_nil
        end.count
      end

      it 'runs the same bounded number of queries however many workload pipelines it looks through' do
        with_two = query_count_after_adding(2)
        with_six = query_count_after_adding(4) # 6 partial scans in total

        expect(with_six).to eq(with_two)
        expect(with_two).to be <= 3
      end
    end

    context 'when the branch has no commit' do
      subject(:branch_scan_pipeline) { described_class.latest_branch_scan_pipeline_for(project, 'no-such-branch') }

      it { is_expected.to be_nil }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it 'returns nil without resolving the branch' do
        create_scan_pipeline(sha: branch_head.id)

        expect(project).not_to receive(:commit)
        expect(branch_scan_pipeline).to be_nil
      end
    end
  end

  describe '.record_scan', :clean_gitlab_redis_shared_state do
    let(:sha) { 'd' * 40 }
    let(:ref) { 'refs/workloads/abc123' }
    let(:source) { :duo_workflow }
    let(:pipeline) { create(:ci_pipeline, project: project, ref: ref, sha: sha, source: source) }
    let(:key) { described_class.scan_marker_key(project.id, sha) }

    def marker_ttl
      Gitlab::Redis::SharedState.with { |redis| redis.ttl(key) }
    end

    it 'sets the marker for the project and commit, expiring with the scan' do
      described_class.record_scan(pipeline)

      expect(marker_ttl).to be_within(5).of(Security::Scan.stale_after.to_i)
    end

    context 'when the pipeline is not a workload' do
      let(:ref) { 'feature-branch' }

      it 'does not set the marker' do
        described_class.record_scan(pipeline)

        expect(marker_ttl).to eq(-2)
      end
    end

    context 'when the workload has another source' do
      let(:source) { :push }

      it 'does not set the marker' do
        described_class.record_scan(pipeline)

        expect(marker_ttl).to eq(-2)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it 'still sets the marker, so turning the flag on does not hide stored scans' do
        described_class.record_scan(pipeline)

        expect(marker_ttl).to be > 0
      end
    end
  end

  describe '.scan_recorded?', :clean_gitlab_redis_shared_state do
    subject(:scan_recorded?) { described_class.scan_recorded?(project, sha) }

    let(:sha) { 'e' * 40 }

    def record_marker
      pipeline = create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', sha: sha, source: :duo_workflow)
      described_class.record_scan(pipeline)
    end

    it 'is true when a scan was recorded for the commit' do
      record_marker

      expect(scan_recorded?).to be(true)
    end

    it 'is false when no scan was recorded for the commit' do
      expect(scan_recorded?).to be(false)
    end

    context 'when the SHA is blank' do
      let(:sha) { nil }

      it { is_expected.to be(false) }
    end

    it 'runs no SQL' do
      record_marker

      expect(ActiveRecord::QueryRecorder.new { scan_recorded? }.count).to eq(0)
    end

    it 'reads Redis once per request' do
      record_marker

      Gitlab::SafeRequestStore.ensure_request_store do
        expect(Gitlab::Redis::SharedState).to receive(:with).once.and_call_original

        expect(Array.new(2) { described_class.scan_recorded?(project, sha) }).to match_array([true, true])
      end
    end
  end

  describe '.scanned_sha' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    it 'returns the source commit for a merged-results pipeline' do
      pipeline = build(:ci_pipeline, :merged_result_pipeline, merge_request: merge_request)

      expect(described_class.scanned_sha(pipeline)).to eq(merge_request.source_branch_sha)
    end

    it 'falls back to the pipeline commit for a merged-results pipeline without a source commit' do
      pipeline = build(:ci_pipeline, :merged_result_pipeline, merge_request: merge_request, sha: 'c' * 40,
        source_sha: nil, target_sha: 'd' * 40)

      expect(described_class.scanned_sha(pipeline)).to eq('c' * 40)
    end

    it 'returns the pipeline commit otherwise, even when a source commit is set' do
      pipeline = build(:ci_pipeline, project: project, sha: 'a' * 40, source_sha: 'b' * 40)

      expect(described_class.scanned_sha(pipeline)).to eq('a' * 40)
    end
  end

  describe '.scan_pipeline_ids_for_pipeline' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    it 'looks up the scan pipelines at the commit the pipeline scanned' do
      pipeline = build(:ci_pipeline, :merged_result_pipeline, merge_request: merge_request)
      allow(described_class).to receive(:scan_pipeline_ids_for)
        .with(project, merge_request.source_branch_sha).and_return([123])

      expect(described_class.scan_pipeline_ids_for_pipeline(pipeline)).to eq([123])
    end
  end

  describe '.scan_pipeline?' do
    subject(:scan_pipeline?) { described_class.scan_pipeline?(pipeline) }

    let(:sha) { 'a' * 40 }

    context 'with a workload pipeline with a succeeded agentic scan' do
      let(:pipeline) { create_scanned_pipeline }

      it { is_expected.to be(true) }
    end

    context 'when the pipeline is not a workload' do
      let(:pipeline) { create_scanned_pipeline(ref: 'feature-branch') }

      it { is_expected.to be(false) }
    end

    context 'when the workload has another source' do
      let(:pipeline) { create_scanned_pipeline(source: :dependency_management_security_update) }

      it { is_expected.to be(false) }
    end

    context 'when the feature flag is disabled' do
      let(:pipeline) { create_scanned_pipeline }

      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when a newer run at the same SHA replaced it' do
      let(:pipeline) { create_scanned_pipeline }

      before do
        pipeline
        create_scanned_pipeline
      end

      it { is_expected.to be(false) }
    end

    context 'when a newer partial run exists at the same SHA' do
      let(:pipeline) { create_scanned_pipeline }

      before do
        pipeline
        create_scanned_pipeline(partial: true)
      end

      it { is_expected.to be(true) }
    end
  end

  describe '.opened_merge_requests_at' do
    subject(:opened_merge_requests) { described_class.opened_merge_requests_at(project, sha) }

    let_it_be_with_refind(:merge_request) { create(:merge_request, source_project: project) }
    let(:sha) { project.commit(merge_request.source_branch).sha }

    it 'returns the open merge request whose latest diff head is the SHA' do
      expect(opened_merge_requests).to contain_exactly(merge_request)
    end

    it 'excludes closed merge requests' do
      merge_request.close!

      expect(opened_merge_requests).to be_empty
    end

    it 'ignores merge requests whose scanned sha is only on an older diff' do
      merge_request.update_column(:latest_merge_request_diff_id, create(:merge_request_diff).id)

      expect(opened_merge_requests).to be_empty
    end

    it 'excludes merge requests of other projects at the SHA' do
      other_merge_request = create(:merge_request, source_project: create(:project, :repository))

      expect(other_merge_request.diff_head_sha).to eq(sha)
      expect(opened_merge_requests).to contain_exactly(merge_request)
    end

    it 'returns the newest merge requests first, up to MAX_MERGE_REQUESTS_TO_SYNC' do
      stub_const("#{described_class}::MAX_MERGE_REQUESTS_TO_SYNC", 2)
      newer, newest = %w[fix markdown].map do |target_branch|
        create(:merge_request, source_project: project, target_branch: target_branch)
      end

      expect(opened_merge_requests.to_a).to eq([newest, newer])
    end
  end
end
