# frozen_string_literal: true

require 'spec_helper'

# A duo_workflow workload pipeline (synthetic refs/workloads/<hash> ref, SHA == default
# branch HEAD) is recognized for default-branch Vulnerability Report ingestion. The MR
# security comparison is covered in ee/spec/models/merge_request/agentic_analyzer_merge_request_spec.rb.
RSpec.describe 'Agentic analyzer security pipeline recognition', feature_category: :vulnerability_management do
  let_it_be(:project) { create(:project, :repository) }

  let(:default_sha) { project.commit(project.default_branch).sha }

  before do
    stub_feature_flags(agentic_analyzer_security_ingestion: true)
  end

  # A duo_workflow workload pipeline carrying a successful SAST Security::Scan, at `sha`.
  def create_workload_scan(sha:, ref: 'refs/workloads/abc123def')
    pipeline = create(:ci_pipeline, project: project, ref: ref, sha: sha, source: :duo_workflow, status: :success)
    build = create(:ci_build, :success, pipeline: pipeline, project: project)
    create(:security_scan, scan_type: :sast, status: :succeeded, build: build)
    pipeline
  end

  describe 'default-branch Vulnerability Report ingestion' do
    it 'recognizes a workload pipeline at default-branch HEAD as ingestible' do
      pipeline = create_workload_scan(sha: default_sha)

      expect(pipeline.workload?).to be(true)
      expect(pipeline.default_branch?).to be(false) # synthetic ref, so the standard gate is false
      expect(Security::AgenticAnalyzer.default_branch_scan?(pipeline)).to be(true)
      expect(Security::Ingestion.ingest_pipeline?(pipeline)).to be(true)
    end

    it 'does NOT recognize a workload pipeline on a non-default SHA' do
      pipeline = create_workload_scan(sha: 'f' * 40)

      expect(Security::AgenticAnalyzer.default_branch_scan?(pipeline)).to be(false)
    end

    it 'is gated by the feature flag' do
      stub_feature_flags(agentic_analyzer_security_ingestion: false)
      pipeline = create_workload_scan(sha: default_sha)

      expect(Security::AgenticAnalyzer.default_branch_scan?(pipeline)).to be(false)
      expect(Security::Ingestion.ingest_pipeline?(pipeline)).to be(false)
    end

    it 'binds the workload to the default-branch tracked context' do
      pipeline = create_workload_scan(sha: default_sha)
      finder = Security::ProjectTrackedContexts::FindOrCreateService.from_pipeline(pipeline)

      expect(finder.context_name).to eq(project.default_branch_or_main)
      expect(finder.is_default).to be(true)
    end
  end
end
