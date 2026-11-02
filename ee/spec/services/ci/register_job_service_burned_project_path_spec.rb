# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::RegisterJobService, 'burned project path on SaaS',
  :saas_gitlab_com_subscriptions, feature_category: :secrets_management do
  let_it_be_with_reload(:project) { create(:project) }
  let(:pipeline) { create(:ci_pipeline, project: project) }
  let(:runner) { create(:ci_runner, :project, projects: [project]) }

  let(:id_tokens) { { 'TEST_ID_TOKEN' => { aud: 'https://example.com' } } }

  context 'when build is on a burned project path' do
    before do
      create(:burned_project_route,
        organization: project.organization,
        path: project.full_path,
        project_id: non_existing_record_id)

      stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
      setting = ApplicationSetting.current || create(:application_setting)
      setting.update_column(:ci_cd_settings,
        setting.ci_cd_settings.merge('block_jwt_for_reclaimed_paths' => false))
      Gitlab::CurrentSettings.expire_current_application_settings
    end

    context 'and the build uses id_tokens with project_path in sub_claim_components' do
      let!(:pending_job) do
        create(:ci_build, :pending, :queued, pipeline: pipeline, id_tokens: id_tokens)
      end

      before do
        project.ci_cd_settings.update!(id_token_sub_claim_components: %w[project_path ref_type ref])
        pending_job.create_queuing_entry!
      end

      it 'drops the build despite the stored false' do
        expect(ApplicationSetting.current.ci_cd_settings['block_jwt_for_reclaimed_paths']).to be(false)
        expect(described_class.new(runner, nil).execute.build).to be_nil
        expect(pending_job.reload).to be_failed
        expect(pending_job.failure_reason).to eq('id_token_burned_project_path')
      end
    end
  end
end
