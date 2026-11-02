# frozen_string_literal: true

require 'spec_helper'

# Drives Security::MergeRequestSecurityReportGenerationService end-to-end with agentic
# duo_workflow workload pipelines as the only head, or on top of a regular head pipeline,
# against regular and agentic analyzer bases, with full and partial scans, and asserts
# which findings the MR security widget report shows as added and fixed.
RSpec.describe 'Agentic analyzer MR widget e2e (report generation)', feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }
  let(:agentic_scanner) do
    create(:vulnerabilities_scanner, project: project, external_id: 'gitlab_bl_security_analyzer',
      name: 'GitLab BL Security Analyzer')
  end

  let(:semgrep_scanner) { create(:vulnerabilities_scanner, project: project, external_id: 'semgrep', name: 'Semgrep') }

  # Not let_it_be: the merge request memoizes its agentic analyzer scan lookups.
  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  before do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
  end

  def create_workload_scan(sha:, ref:)
    pipeline = create(:ci_pipeline, project: project, ref: ref, sha: sha, source: :duo_workflow, status: :success)
    create(:duo_workflows_workload, workload: create(:ci_workload, pipeline: pipeline),
      workflow: create(:duo_workflows_workflow, project: project,
        workflow_definition: Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE))
    build = create(:ci_build, :success, pipeline: pipeline, project: project)
    create(:security_scan, scan_type: :sast, status: :succeeded, build: build)
  end

  # A regular pipeline with a SAST scan, as a Semgrep or GitLab Advanced SAST job publishes it.
  def create_regular_scan(ref:, sha:)
    pipeline = create(:ci_pipeline, project: project, ref: ref, sha: sha, status: :success)
    build = create(:ci_build, :success, pipeline: pipeline, project: project)
    create(:security_scan, scan_type: :sast, status: :succeeded, build: build)
  end

  def create_finding(scan, scanner, uuid: SecureRandom.uuid)
    create(:security_finding, scan: scan, scanner: scanner, uuid: uuid, deduplicated: true)
  end

  def scanner_ids(findings)
    findings.map { |finding| finding.dig('scanner', 'external_id') }
  end

  def run_report(params)
    service = Security::MergeRequestSecurityReportGenerationService.new(merge_request, params)
    # ReactiveCaching would only enqueue the comparison and return :parsing, so run it inline
    # (calculate_reactive_cache is private, hence not the shared synchronous_reactive_cache helper).
    allow(service).to receive(:with_reactive_cache) do |*args, &block|
      block.call(service.send(:calculate_reactive_cache, *args))
    end
    service.execute
  end

  it 'resolves the agentic workload pipeline as MR security head and generates a parsed report' do
    head_scan = create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/headabc')
    # `deduplicated` defaults to false and Security::FindingsFinder only returns deduplicated
    # findings, so without this the finding never reaches the head report and the diff is empty.
    create(:security_finding, scan: head_scan, scanner: agentic_scanner, severity: :high, deduplicated: true)

    report = run_report({ report_type: 'sast' })

    expect(report[:status]).to eq(:parsed)

    # The comparison payload nests the diff under `:data`, the same shape the service itself reads
    # back via `report.dig(:data, 'added')`. Reading `report[:added]` returns nil and the size
    # assertion below dies on nil rather than reporting a real miss.
    added = report.dig(:data, 'added')

    # Base has no scan -> our agentic finding is a NEW (added) finding in the widget.
    expect(added.size).to be >= 1
    expect(added.map do |f|
      f['scanner']&.dig('external_id') || f.dig(:scanner, :external_id)
    end).to include('gitlab_bl_security_analyzer')
  end

  context 'when the head agentic analyzer scan is partial' do
    before do
      base_scan = create_workload_scan(sha: project.commit(merge_request.target_branch).id, ref: 'refs/workloads/base')
      create(:security_finding, scan: base_scan, scanner: agentic_scanner, severity: :high, deduplicated: true)

      # The partial head scan covers only changed files, so it does not re-detect the base finding.
      head_scan = create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/head')
      create(:vulnerabilities_partial_scan, scan: head_scan)
    end

    it 'suppresses "fixed" for the partial scan mode the widget derives from enabledPartialSecurityScans' do
      report = run_report(report_type: 'sast', scan_mode: 'partial')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed')).to be_empty
    end

    it 'reports the base finding as fixed when no scan mode is sent' do
      report = run_report(report_type: 'sast')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed').size).to eq(1)
    end
  end

  context 'when both the regular head pipeline and the agentic analyzer scan have SAST findings' do
    before do
      head_scan = create_regular_scan(ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      merge_request.update!(head_pipeline: head_scan.pipeline)
      create_finding(head_scan, semgrep_scanner)

      create_finding(
        create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/head'), agentic_scanner
      )
    end

    it 'reports the findings of both scanners as added' do
      report = run_report(report_type: 'sast')

      expect(report[:status]).to eq(:parsed)
      expect(scanner_ids(report.dig(:data, 'added'))).to contain_exactly('semgrep', 'gitlab_bl_security_analyzer')
    end

    context 'when agentic_analyzer_security_ingestion is disabled' do
      before do
        stub_feature_flags(agentic_analyzer_security_ingestion: false)
      end

      it 'reports only the regular head pipeline findings, as before' do
        report = run_report(report_type: 'sast')

        expect(report[:status]).to eq(:parsed)
        expect(scanner_ids(report.dig(:data, 'added'))).to contain_exactly('semgrep')
      end
    end
  end

  context 'when the agentic analyzer scan is the only head and the target branch also has regular SAST' do
    let(:target_sha) { project.commit(merge_request.target_branch).id }
    let(:existing_uuid) { SecureRandom.uuid }
    let(:head_scan) { create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/head') }
    let(:new_finding) { create_finding(head_scan, agentic_scanner) }

    before do
      regular_base_scan = create_regular_scan(ref: merge_request.target_branch, sha: target_sha)
      create_finding(regular_base_scan, semgrep_scanner)
      allow(merge_request).to receive(:latest_scan_finding_comparison_pipeline).and_return(regular_base_scan.pipeline)

      create_finding(
        create_workload_scan(sha: target_sha, ref: 'refs/workloads/base'), agentic_scanner, uuid: existing_uuid
      )
      create_finding(head_scan, agentic_scanner, uuid: existing_uuid)
      new_finding
    end

    it 'compares against the agentic analyzer base: no regular SAST finding is "fixed", only new findings are added' do
      report = run_report(report_type: 'sast')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed')).to be_empty
      expect(report.dig(:data, 'added').pluck('uuid')).to contain_exactly(new_finding.uuid)
    end
  end

  context 'when the regular head pipeline ran no SAST scan and the target branch has regular SAST' do
    let(:target_sha) { project.commit(merge_request.target_branch).id }

    before do
      merge_request.update!(head_pipeline: create(:ci_pipeline, :success, project: project,
        ref: merge_request.source_branch, sha: merge_request.diff_head_sha))

      regular_base_scan = create_regular_scan(ref: merge_request.target_branch, sha: target_sha)
      create_finding(regular_base_scan, semgrep_scanner)
      allow(merge_request).to receive(:latest_scan_finding_comparison_pipeline).and_return(regular_base_scan.pipeline)

      create_workload_scan(sha: target_sha, ref: 'refs/workloads/base')
      create_finding(
        create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/head'), agentic_scanner
      )
    end

    it 'compares against the agentic analyzer base, so no regular SAST finding is reported as fixed' do
      report = run_report(report_type: 'sast', scan_mode: 'full')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed')).to be_empty
      expect(scanner_ids(report.dig(:data, 'added'))).to contain_exactly('gitlab_bl_security_analyzer')
    end
  end

  context 'when a regular head pipeline has no agentic analyzer scan but the target branch has one' do
    before do
      head_scan = create_regular_scan(ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      merge_request.update!(head_pipeline: head_scan.pipeline)
      create_finding(head_scan, semgrep_scanner)

      target_sha = project.commit(merge_request.target_branch).id
      create_finding(create_workload_scan(sha: target_sha, ref: 'refs/workloads/base'), agentic_scanner)
    end

    it 'does not report the agentic analyzer findings of the target branch as fixed' do
      report = run_report(report_type: 'sast', scan_mode: 'full')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed')).to be_empty
    end
  end

  context 'when both the target branch and the head have regular and agentic analyzer scans' do
    let(:target_sha) { project.commit(merge_request.target_branch).id }
    let(:shared_uuids) { Array.new(2) { SecureRandom.uuid } }
    let(:fixed_uuid) { SecureRandom.uuid }

    before do
      head_scan = create_regular_scan(ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      merge_request.update!(head_pipeline: head_scan.pipeline)
      create_finding(head_scan, semgrep_scanner, uuid: shared_uuids.first)

      regular_base_scan = create_regular_scan(ref: merge_request.target_branch, sha: target_sha)
      create_finding(regular_base_scan, semgrep_scanner, uuid: shared_uuids.first)
      allow(merge_request).to receive(:latest_scan_finding_comparison_pipeline).and_return(regular_base_scan.pipeline)

      agentic_base_scan = create_workload_scan(sha: target_sha, ref: 'refs/workloads/base')
      create_finding(agentic_base_scan, agentic_scanner, uuid: shared_uuids.last)
      create_finding(agentic_base_scan, agentic_scanner, uuid: fixed_uuid)
      create_finding(
        create_workload_scan(sha: merge_request.diff_head_sha, ref: 'refs/workloads/head'), agentic_scanner,
        uuid: shared_uuids.last
      )
    end

    it 'treats an agentic analyzer finding on both sides as existing and one only on the base as fixed' do
      report = run_report(report_type: 'sast', scan_mode: 'full')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'added')).to be_empty
      expect(report.dig(:data, 'fixed').pluck('uuid')).to contain_exactly(fixed_uuid)
    end
  end

  context 'when the agentic analyzer scan on top of a regular head pipeline is partial' do
    # The fixture report attached to the partial scan's build names this scanner, standing in
    # for the agentic analyzer scan's own report.
    let(:partial_scanner) { create(:vulnerabilities_scanner, project: project, external_id: 'find_sec_bugs') }

    before do
      head_scan = create_regular_scan(ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      merge_request.update!(head_pipeline: head_scan.pipeline)

      target_sha = project.commit(merge_request.target_branch).id
      create_finding(create_workload_scan(sha: target_sha, ref: 'refs/workloads/base'), partial_scanner)

      pipeline = create(:ci_pipeline, project: project, ref: 'refs/workloads/head', sha: merge_request.diff_head_sha,
        source: :duo_workflow, status: :success)
      build = create(:ci_build, :success, :sast_report, pipeline: pipeline, project: project)
      create(:vulnerabilities_partial_scan, scan: create(:security_scan, scan_type: :sast, status: :succeeded,
        build: build))
    end

    it 'does not report its base findings as fixed in the full scan comparison' do
      report = run_report(report_type: 'sast', scan_mode: 'full')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed')).to be_empty
    end
  end

  context 'when the head has both a full and a partial agentic analyzer scan' do
    let(:agentic_report_scanner) { create(:vulnerabilities_scanner, project: project, external_id: 'find_sec_bugs') }
    let(:uuids) { Array.new(3) { SecureRandom.uuid } }

    def create_head_report_scan
      pipeline = create(:ci_pipeline, project: project, ref: 'refs/workloads/head', sha: merge_request.diff_head_sha,
        source: :duo_workflow, status: :success)
      build = create(:ci_build, :success, :sast_report, pipeline: pipeline, project: project)
      create(:security_scan, scan_type: :sast, status: :succeeded, build: build)
    end

    before do
      base_scan = create_workload_scan(sha: project.commit(merge_request.target_branch).id, ref: 'refs/workloads/base')
      create_finding(base_scan, agentic_report_scanner, uuid: uuids[0])
      create_finding(base_scan, agentic_report_scanner, uuid: uuids[1])

      create_finding(create_head_report_scan, agentic_report_scanner, uuid: uuids[0])
      partial_scan = create_head_report_scan
      create(:vulnerabilities_partial_scan, scan: partial_scan)
      create_finding(partial_scan, agentic_report_scanner, uuid: uuids[2])
    end

    it 'reports the base finding the full scan no longer detects as fixed' do
      report = run_report(report_type: 'sast', scan_mode: 'full')

      expect(report[:status]).to eq(:parsed)
      expect(report.dig(:data, 'fixed').pluck('uuid')).to contain_exactly(uuids[1])
    end
  end
end
