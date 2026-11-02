# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequest, 'agentic analyzer security comparison', :clean_gitlab_redis_shared_state,
  feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }

  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  before do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
  end

  # A duo_workflow workload pipeline of the BLSA flow at `sha` with a succeeded SAST scan, as the agentic
  # analyzer publishes it. `record: false` leaves out the marker Security::StoreScansService would set when
  # storing the scan.
  def create_agentic_scan_pipeline(sha:, sast_report: false, record: true)
    pipeline = create(:ci_pipeline, :success, project: project, ref: 'refs/workloads/abc123', sha: sha,
      source: :duo_workflow)
    create(:duo_workflows_workload, workload: create(:ci_workload, pipeline: pipeline),
      workflow: create(:duo_workflows_workflow, project: project,
        workflow_definition: Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE))
    build_traits = sast_report ? [:success, :sast_report] : [:success]
    build = create(:ci_build, *build_traits, pipeline: pipeline, project: project)
    create(:security_scan, scan_type: :sast, status: :succeeded, build: build, latest: true)
    Security::AgenticAnalyzer.record_scan(pipeline) if record
    pipeline
  end

  # A regular MR head pipeline, optionally with a succeeded scan of `scan_type` (with one finding by default).
  def create_head_pipeline(scan_type: nil, with_finding: true)
    pipeline = create(:ci_pipeline, :success, project: project, ref: merge_request.source_branch,
      sha: merge_request.diff_head_sha)
    merge_request.update!(head_pipeline: pipeline)

    if scan_type
      build = create(:ci_build, :success, pipeline: pipeline, project: project)
      scan = create(:security_scan, scan_type: scan_type, status: :succeeded, build: build, latest: true)
      create(:security_finding, scan: scan, deduplicated: true) if with_finding
    end

    pipeline
  end

  describe '#security_comparison_head_pipeline' do
    context 'when there is no regular head pipeline' do
      let!(:agentic_pipeline) { create_agentic_scan_pipeline(sha: merge_request.diff_head_sha) }

      it 'uses the agentic workload pipeline for SAST' do
        expect(merge_request.diff_head_pipeline).to be_nil
        expect(merge_request.security_comparison_head_pipeline('sast')).to eq(agentic_pipeline)
      end

      it 'keeps diff_head_pipeline for other report types' do
        expect(merge_request.security_comparison_head_pipeline('dependency_scanning')).to be_nil
      end

      it 'looks up the agentic pipeline once per report type' do
        expect(Security::AgenticAnalyzer).to receive(:scan_pipeline_for).once.and_call_original

        2.times { expect(merge_request.security_comparison_head_pipeline('sast')).to eq(agentic_pipeline) }
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it 'does not look up the agentic pipeline' do
          expect(Security::AgenticAnalyzer).not_to receive(:scan_pipeline_for)

          expect(merge_request.security_comparison_head_pipeline('sast')).to be_nil
        end
      end
    end

    context 'when there is a regular head pipeline and an agentic scan' do
      it 'keeps diff_head_pipeline, the agentic pipeline being compared alongside it' do
        head = create_head_pipeline
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)

        expect(merge_request.security_comparison_head_pipeline('sast')).to eq(head)
        expect(merge_request.security_comparison_head_pipeline('dependency_scanning')).to eq(head)
      end
    end

    context 'when the regular head pipeline has no scans and there is no agentic scan' do
      it 'returns the regular head pipeline' do
        head = create_head_pipeline

        expect(merge_request.security_comparison_head_pipeline('sast')).to eq(head)
      end
    end
  end

  describe '#agentic_sast_reports?' do
    before do
      stub_licensed_features(sast: true)
    end

    it 'is true when the scan marker is set and an agentic SAST scan exists' do
      create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)

      expect(merge_request.agentic_sast_reports?).to be(true)
    end

    context 'when no scan marker was recorded for the commit' do
      before do
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true, record: false)
      end

      it 'is false without querying CI or security scans' do
        merge_request.diff_head_sha # warm up the MR diff outside the recorder

        recorder = ActiveRecord::QueryRecorder.new { expect(merge_request.agentic_sast_reports?).to be(false) }

        expect(recorder.log.grep(/p_ci_|security_scans/)).to be_empty
      end
    end
  end

  describe '#has_sast_reports?' do
    before do
      stub_licensed_features(sast: true)
    end

    context 'when only the agentic workload pipeline has a SAST report' do
      before do
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)
      end

      it 'returns true' do
        expect(merge_request.has_sast_reports?).to be(true)
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it 'returns false without resolving the agentic pipeline' do
          expect(Security::AgenticAnalyzer).not_to receive(:scan_pipeline_for)

          expect(merge_request.has_sast_reports?).to be(false)
        end
      end

      context 'when rendered through Rapid Diffs' do
        let!(:older_diff_id) { merge_request.merge_request_diff.id }
        let(:latest_version) { MergeRequests::VersionedMergeRequest.new(merge_request) }
        let(:older_version) do
          MergeRequests::VersionedMergeRequest.new(merge_request, version_params: { diff_id: older_diff_id })
        end

        before do
          merge_request.create_merge_request_diff
          merge_request.reload
        end

        it 'returns true for the latest version only' do
          expect(latest_version.has_sast_reports?).to be(true)
          expect(older_version.has_sast_reports?).to be(false)
        end
      end
    end

    context 'when the regular head pipeline has no SAST report but the agentic workload pipeline does' do
      it 'returns true' do
        create_head_pipeline(scan_type: :dependency_scanning)
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha, sast_report: true)

        expect(merge_request.has_sast_reports?).to be(true)
      end
    end
  end

  describe '#comparison_base_pipeline' do
    subject(:base_pipeline) do
      merge_request.comparison_base_pipeline(Vulnerabilities::CompareSecurityReportsService, report_type)
    end

    let(:report_type) { 'sast' }

    let!(:agentic_pipeline) do
      create_agentic_scan_pipeline(sha: project.commit(merge_request.target_branch).id)
    end

    it 'falls back to the agentic scan of the target branch HEAD when the head has an agentic scan too' do
      create_head_pipeline(scan_type: :sast)
      create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)

      expect(base_pipeline).to eq(agentic_pipeline)
    end

    it 'resolves the base pipeline once per report type' do
      create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)

      expect(merge_request).to receive(:agentic_security_comparison?).once.and_call_original

      2.times do
        expect(merge_request.comparison_base_pipeline(Vulnerabilities::CompareSecurityReportsService, 'sast'))
          .to eq(agentic_pipeline)
      end
    end

    context 'when a regular head pipeline has no agentic scan' do
      before do
        create_head_pipeline(scan_type: :sast)
      end

      it 'does not fall back to the agentic scan, whose findings would all be reported as fixed' do
        expect(base_pipeline).to be_nil
      end
    end

    context 'when the target branch moved on since its last agentic scan' do
      let!(:agentic_pipeline) do
        create_agentic_scan_pipeline(sha: project.commit(merge_request.target_branch).parent_id)
      end

      it 'falls back to that scan' do
        create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)

        expect(base_pipeline).to eq(agentic_pipeline)
      end
    end

    context 'when there is a regular base pipeline' do
      let(:regular_base) { create(:ci_pipeline, :success, project: project, ref: merge_request.target_branch) }

      before do
        allow(merge_request).to receive(:latest_scan_finding_comparison_pipeline).and_return(regular_base)
      end

      it 'uses the regular base pipeline' do
        expect(base_pipeline).to eq(regular_base)
      end

      context 'when the only head pipeline is an agentic scan' do
        before do
          create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)
        end

        it 'compares against the agentic scan so other scanners are not reported as fixed' do
          expect(base_pipeline).to eq(agentic_pipeline)
        end
      end

      context 'when the regular head pipeline ran no SAST scan and there is an agentic head scan' do
        before do
          create_head_pipeline(scan_type: :dependency_scanning)
          create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)
        end

        it 'compares against the agentic scan so the regular SAST findings are not reported as fixed' do
          expect(base_pipeline).to eq(agentic_pipeline)
        end
      end

      context 'when the SAST scan is in a child pipeline of the regular head pipeline' do
        before do
          child = create(:ci_pipeline, :success, project: project, child_of: create_head_pipeline)
          build = create(:ci_build, :success, pipeline: child, project: project)
          create(:security_scan, scan_type: :sast, status: :succeeded, build: build, latest: true)
          create_agentic_scan_pipeline(sha: merge_request.diff_head_sha)
        end

        it 'keeps the regular base pipeline' do
          expect(base_pipeline).to eq(regular_base)
        end

        it 'checks the head pipeline scan once per report type' do
          expect(Security::AgenticAnalyzer).to receive(:pipeline_has_successful_scan?).once.and_call_original

          2.times { merge_request.comparison_base_pipeline(Vulnerabilities::CompareSecurityReportsService, 'sast') }
        end
      end
    end

    context 'when the target branch has a CI pipeline with security reports' do
      let!(:ci_base_pipeline) do
        create(:ee_ci_pipeline, :with_sast_report, project: project, ref: merge_request.target_branch,
          sha: project.commit(merge_request.target_branch).id)
      end

      it 'prefers the CI pipeline over the agentic scan' do
        expect(base_pipeline).to eq(ci_base_pipeline)
      end
    end

    context 'for a non-SAST report type' do
      let(:report_type) { 'dependency_scanning' }

      it 'does not fall back to the agentic scan' do
        expect(base_pipeline).to be_nil
      end
    end

    context 'without a report type' do
      let(:report_type) { nil }

      it 'does not fall back to the agentic scan' do
        expect(base_pipeline).to be_nil
      end
    end

    context 'when the target branch has no commit' do
      before do
        allow(merge_request.project).to receive(:commit).and_call_original
        allow(merge_request.project).to receive(:commit).with(merge_request.target_branch).and_return(nil)
      end

      it 'returns nil' do
        expect(base_pipeline).to be_nil
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it 'does not resolve the target branch commit' do
        expect(merge_request.project).not_to receive(:commit).with(merge_request.target_branch)

        expect(base_pipeline).to be_nil
      end
    end
  end

  describe '#security_comparison_additional_pipeline_ids' do
    subject(:additional_ids) { merge_request.security_comparison_additional_pipeline_ids(report_type) }

    let(:report_type) { 'sast' }
    let(:regular_base) { create(:ci_pipeline, :success, project: project, ref: merge_request.target_branch) }
    let!(:agentic_base) { create_agentic_scan_pipeline(sha: project.commit(merge_request.target_branch).id) }
    let!(:agentic_head) { create_agentic_scan_pipeline(sha: merge_request.diff_head_sha) }

    before do
      allow(merge_request).to receive(:latest_scan_finding_comparison_pipeline).and_return(regular_base)
    end

    context 'when the MR has regular head and base pipelines' do
      before do
        create_head_pipeline(scan_type: :sast)
      end

      it 'adds the agentic head and base scans to the comparison' do
        expect(additional_ids).to eq(
          additional_head_pipeline_ids: [agentic_head.id],
          additional_base_pipeline_ids: [agentic_base.id]
        )
      end

      context 'for a report type the agentic analyzer does not publish' do
        let(:report_type) { 'dependency_scanning' }

        it { is_expected.to eq({}) }
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it { is_expected.to eq({}) }
      end
    end

    context 'when a regular head pipeline has no agentic scan' do
      let!(:agentic_head) { nil }

      before do
        create_head_pipeline(scan_type: :sast)
      end

      it 'adds no agentic base scan, whose findings would all be reported as fixed' do
        expect(additional_ids).to eq({})
      end
    end

    context 'when no head pipeline resolves for the report type' do
      before do
        create_head_pipeline(scan_type: :sast)
        allow(merge_request).to receive(:security_comparison_head_pipeline).with(report_type).and_return(nil)
      end

      it 'adds every agentic head scan' do
        expect(additional_ids[:additional_head_pipeline_ids]).to eq([agentic_head.id])
      end
    end

    context 'when the agentic scans are the head and base pipelines themselves' do
      it 'adds nothing' do
        expect(additional_ids).to eq({})
      end
    end
  end
end
