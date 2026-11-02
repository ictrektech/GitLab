# frozen_string_literal: true

require 'spec_helper'

# Scan-result (approval) policies see agentic-analyzer findings: the RelatedPipelines concern
# (used by UpdateApprovalsService to source findings) unions in recognized agentic duo_workflow
# workload pipelines at the same sha.
RSpec.describe 'Agentic findings visible to scan-result policy pipeline resolution',
  feature_category: :security_policy_management do
  let_it_be(:project) { create(:project, :repository) }
  let(:sha) { project.commit(project.default_branch).sha }

  let(:harness) do
    Class.new do
      include Security::ScanResultPolicies::RelatedPipelines

      def merge_request; end
    end.new
  end

  # a normal head pipeline (what the policy drives from) + an agentic workload pipeline at the same sha
  let!(:head) do
    create(:ci_pipeline, project: project, ref: project.default_branch, sha: sha, source: :push, status: :success)
  end

  let!(:workload) do
    p = create(:ci_pipeline, project: project, ref: 'refs/workloads/pol123', sha: sha, source: :duo_workflow,
      status: :success)
    b = create(:ci_build, :success, name: 'workload', pipeline: p, project: project)
    scanner = create(:vulnerabilities_scanner, project: project, external_id: 'gitlab_bl_security_analyzer',
      name: 'GitLab BL Analyzer')
    scan = create(:security_scan, scan_type: :sast, status: :succeeded, build: b, latest: true)
    create(:security_finding, :with_finding_data, scan: scan, scanner: scanner, severity: :high, deduplicated: true)
    p
  end

  it 'EXCLUDES the agentic workload pipeline when the FF is off (baseline)' do
    stub_feature_flags(agentic_analyzer_security_ingestion: false)
    expect(harness.related_pipeline_ids(head)).not_to include(workload.id)
  end

  it 'INCLUDES the agentic workload pipeline when the FF is on' do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
    ids = harness.related_pipeline_ids(head)
    expect(ids).to include(head.id, workload.id)

    # and the policy finding-finder over those pipelines returns the agentic finding
    findings = Security::ScanResultPolicies::FindingsFinder.new(
      project, head, { related_pipeline_ids: ids, scanners: %w[sast] }
    ).execute
    expect(findings.to_a.filter_map { |f| f.scanner&.external_id }).to include('gitlab_bl_security_analyzer')
  end
end
