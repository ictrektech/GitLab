# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/_general.html.haml', feature_category: :groups_and_projects do
  let_it_be(:group) { build_stubbed(:group) }
  let_it_be(:user) { build_stubbed(:admin) }

  before do
    assign(:group, group)
    allow(view).to receive(:current_user).and_return(user)
  end

  context 'when group_general_settings_vue is disabled' do
    before do
      stub_feature_flags(group_general_settings_vue: false)
    end

    describe 'Group Settings README' do
      it 'renders #js-group-settings-readme' do
        render

        expect(rendered).to have_selector('#js-group-settings-readme')
      end
    end
  end

  context 'when group_general_settings_vue is enabled' do
    before do
      stub_feature_flags(group_general_settings_vue: true)
      allow(view).to receive(:group_general_settings_data).and_return({})
    end

    it 'renders the Vue mount point instead of the HAML form fields' do
      render

      expect(rendered).to have_selector('#js-group-general-settings')
      expect(rendered).not_to have_selector('#group_name_edit')
    end
  end
end
