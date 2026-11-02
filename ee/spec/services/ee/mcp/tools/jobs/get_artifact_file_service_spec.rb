# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Jobs::GetArtifactFileService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :public, developers: [user]) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:job) { create(:ci_build, :success, :artifacts, pipeline: pipeline, name: 'rspec') }

  let(:service) { described_class.new(name: 'get_artifact_file', version: '0.1.0') }

  before do
    service.set_cred(current_user: user, access_token: build_stubbed(:personal_access_token, user: user))
  end

  def call(artifact_path)
    service.execute(params: { name: 'get_artifact_file',
                              arguments: { project_id: project.full_path, job_id: job.id,
                                           artifact_path: artifact_path } })
  end

  def set_exclusion_rules(rules)
    project.project_setting.update!(duo_context_exclusion_settings: { 'exclusion_rules' => rules })
  end

  context 'when the project has no exclusion rules' do
    it 'returns the artifact file' do
      expect(call('ci_artifacts.txt')[:isError]).to be_falsey
    end
  end

  context 'when the path matches an exclusion rule' do
    before do
      set_exclusion_rules(['*.txt'])
    end

    it 'refuses to return the file' do
      result = call('ci_artifacts.txt')

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include('is excluded from AI context')
      expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
    end

    it 'does not open the artifacts archive' do
      expect(Zip::File).not_to receive(:open)

      call('ci_artifacts.txt')
    end
  end

  context 'when the rule does not match the path' do
    before do
      set_exclusion_rules(['*.jpg'])
    end

    it 'returns the file' do
      expect(call('ci_artifacts.txt')[:isError]).to be_falsey
    end
  end

  context 'when a negation rule re-includes the path' do
    before do
      set_exclusion_rules(['*.txt', '!ci_artifacts.txt'])
    end

    it 'returns the file' do
      expect(call('ci_artifacts.txt')[:isError]).to be_falsey
    end
  end

  context 'when a report artifact matches an exclusion rule' do
    let_it_be(:report_job) { create(:ci_build, :success, pipeline: pipeline, name: 'sast') }
    let_it_be(:sast_artifact) { create(:ci_job_artifact, :sast, job: report_job) }

    before do
      set_exclusion_rules(['gl-sast-report.json'])
    end

    it 'refuses to return the report', :aggregate_failures do
      result = service.execute(params: { name: 'get_artifact_file',
                                         arguments: { project_id: project.full_path, job_id: report_job.id,
                                                      file_type: 'sast' } })

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("File 'gl-sast-report.json' is excluded from AI context")
      expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
    end
  end
end
