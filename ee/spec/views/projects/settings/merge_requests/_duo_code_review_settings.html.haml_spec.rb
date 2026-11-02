# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/settings/merge_requests/_duo_code_review_settings', feature_category: :duo_chat do
  subject(:rendered) { view.render('projects/settings/merge_requests/duo_code_review_settings') }

  let_it_be(:project) { build_stubbed(:project) }

  before do
    view.instance_variable_set(:@project, project)
  end

  context 'when duo_features_enabled is false' do
    before do
      allow(project).to receive(:duo_features_enabled).and_return(false)
    end

    it 'renders nothing' do
      expect(rendered).to be_nil
    end
  end

  context 'when duo_features_enabled is true' do
    before do
      allow(project).to receive(:duo_features_enabled).and_return(true)
    end

    context 'when duo_code_review_dap_available? is true' do
      before do
        allow(project).to receive(:duo_code_review_dap_available?).and_return(true)
      end

      it 'renders the auto_duo_code_review_on_push_enabled checkbox' do
        expect(rendered).to have_css(
          'input[name="project[project_setting_attributes][auto_duo_code_review_on_push_enabled]"]'
        )
      end
    end

    context 'when duo_code_review_dap_available? is false' do
      before do
        allow(project).to receive(:duo_code_review_dap_available?).and_return(false)
      end

      it 'does not render the auto_duo_code_review_on_push_enabled checkbox' do
        expect(rendered).not_to have_css(
          'input[name="project[project_setting_attributes][auto_duo_code_review_on_push_enabled]"]'
        )
      end
    end
  end
end
