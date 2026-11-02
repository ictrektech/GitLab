# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::CreatePipelineService, feature_category: :secrets_management do
  let(:downstream_project) { create(:project, path: 'project', namespace: create(:namespace, path: 'some')) }

  let_it_be(:project) { create(:project, :readme) }
  let(:user) { project.first_owner }
  let(:service) { described_class.new(project, user, { ref: 'refs/heads/master' }) }

  let(:config) do
    <<~YAML
    test_openbao_direct:
      secrets:
        TEST_SECRET:
          gitlab_secrets_manager:
            name: foo
      script:
      - echo "testing Openbao in CI"
      - cat $TEST_SECRET
      - echo "done."
    YAML
  end

  before do
    downstream_project.add_developer(user)
    stub_ci_pipeline_yaml_file(config)
  end

  it 'persists pipeline' do
    pipeline = create_pipeline!
    expect(pipeline).to be_persisted

    job = pipeline.builds.find_by_name('test_openbao_direct')
    expect(job).not_to be_failed
  end

  context 'when a secret uses a group source the project cannot access' do
    let_it_be(:unrelated_group) { create(:group) }

    let(:config) do
      <<~YAML
      needs_group_secret:
        when: manual
        secrets:
          TEST_SECRET:
            gitlab_secrets_manager:
              name: foo
              source: group/#{unrelated_group.full_path}
        script: echo "needs secret"
      other_job:
        script: echo "no secrets"
      YAML
    end

    it 'creates the pipeline with all jobs', :aggregate_failures do
      pipeline = create_pipeline!

      expect(pipeline).to be_persisted
      expect(pipeline).not_to be_config_error
      expect(pipeline.builds.map(&:name)).to contain_exactly('needs_group_secret', 'other_job')
    end

    context 'when secrets_manager_defer_group_source_check is disabled' do
      before do
        stub_feature_flags(secrets_manager_defer_group_source_check: false)
      end

      it 'fails the pipeline with a config error and creates no jobs', :aggregate_failures do
        pipeline = create_pipeline!

        expect(pipeline).to be_failed
        expect(pipeline).to be_config_error
        expect(pipeline.builds).to be_empty
        expect(pipeline.error_messages.map(&:content)).to include(
          a_string_including("source group with path '#{unrelated_group.full_path}' not found")
        )
      end
    end
  end

  def create_pipeline!
    service.execute(:push).payload
  end
end
