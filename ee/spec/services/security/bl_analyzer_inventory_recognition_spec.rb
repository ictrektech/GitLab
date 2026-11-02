# frozen_string_literal: true

require 'spec_helper'

# A recognized agentic default-branch workload scan surfaces the Business Logic analyzer in
# Security Inventory, i.e. produces a Security::AnalyzerProjectStatus row of the
# `business_logic` analyzer_type.
RSpec.describe 'BL analyzer Security Inventory recognition (default branch)',
  feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }
  let(:default_sha) { project.commit(project.default_branch).sha }

  before do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
    stub_feature_flags(analyzers_status_from_security_scans: true) # scan-based status path
  end

  # A workload pipeline at default-branch HEAD, shaped like production: the CI job is named
  # `workload` and the SAST report's findings come from the BL scanner.
  def create_bl_workload(sha:)
    pipeline = create(:ci_pipeline, project: project, ref: 'refs/workloads/blabc',
      sha: sha, source: :duo_workflow, status: :success)
    build = create(:ci_build, :success, name: 'workload', pipeline: pipeline, project: project)
    scan = create(:security_scan, scan_type: :sast, status: :succeeded, build: build, latest: true)
    scanner = create(:vulnerabilities_scanner, project: project, external_id: 'gitlab_bl_security_analyzer')
    create(:security_finding, scan: scan, scanner: scanner)
    pipeline
  end

  it 'maps the BL workload scan to the business_logic analyzer_type and writes an Inventory status row' do
    pipeline = create_bl_workload(sha: default_sha)

    Security::AnalyzersStatus::UpdateService.new(pipeline).execute

    row = Security::AnalyzerProjectStatus.by_projects(project).find_by(analyzer_type: :business_logic)
    expect(row).to be_present
    expect(row.status).to eq('success')
  end
end
