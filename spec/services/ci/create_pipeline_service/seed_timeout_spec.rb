# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a pipeline with the seed timeout', feature_category: :pipeline_composition do
  let_it_be(:project) { create(:project, :small_repo) }
  let_it_be(:user) { project.first_owner }

  let(:service) { Ci::CreatePipelineService.new(project, user, ref: 'refs/heads/master') }

  subject(:pipeline) { service.execute(:push, save_on_errors: true).payload }

  before do
    stub_ci_pipeline_yaml_file(<<~YAML)
      job1:
        script: echo
      job2:
        script: echo
        rules:
          - if: $CI_COMMIT_TAG
    YAML

    stub_feature_flags(ci_pipeline_seed_timeout_override: false)
  end

  context 'when seeding takes longer than the timeout' do
    before do
      stub_const('Gitlab::Ci::Pipeline::Chain::Seed::TIMEOUT_SECONDS', -1.second)
    end

    it 'persists a failed pipeline without jobs' do
      expect(pipeline).to be_persisted
      expect(pipeline).to be_failed
      expect(pipeline).to be_seed_timeout
      expect(pipeline.statuses).to be_empty
      expect(pipeline.errors.full_messages.first)
        .to start_with('Pipeline creation timed out while evaluating rules.')
    end

    context 'when ci_pipeline_seed_timeout is disabled' do
      before do
        stub_feature_flags(ci_pipeline_seed_timeout: false)
      end

      it 'creates the pipeline' do
        expect(pipeline).to be_created_successfully
        expect(pipeline.builds.map(&:name)).to contain_exactly('job1')
      end
    end

    context 'when the override feature flag is enabled for the root namespace' do
      before do
        stub_feature_flags(ci_pipeline_seed_timeout_override: project.root_namespace)
      end

      it 'creates the pipeline' do
        expect(pipeline).to be_created_successfully
        expect(pipeline.builds.map(&:name)).to contain_exactly('job1')
      end
    end
  end

  context 'when seeding finishes before the timeout' do
    it 'creates the pipeline' do
      expect(pipeline).to be_created_successfully
      expect(pipeline.builds.map(&:name)).to contain_exactly('job1')
    end
  end
end
