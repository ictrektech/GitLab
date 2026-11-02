# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Settings::MergeRequestsController, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:decisions_available) { true }

  before do
    sign_in(user)

    allow_next_found_instance_of(Project) do |instance|
      allow(instance).to receive(:duo_code_review_decisions_available?).and_return(decisions_available)
    end
  end

  describe 'PATCH #update' do
    subject(:update_settings) do
      patch project_settings_merge_requests_path(project), params: {
        project: { project_setting_attributes: { duo_code_review_decisions_enabled: false } }
      }
    end

    it 'persists the decisions setting' do
      update_settings

      expect(project.project_setting.reload.attributes).to include('duo_code_review_decisions_enabled' => false)
    end

    context 'when Duo code review decisions are not available' do
      let(:decisions_available) { false }

      it 'does not permit the decisions setting' do
        update_settings

        expect(project.project_setting.reload.attributes).to include('duo_code_review_decisions_enabled' => nil)
      end
    end
  end
end
