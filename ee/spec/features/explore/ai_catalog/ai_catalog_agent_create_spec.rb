# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AI Catalog', :js, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include ListboxHelpers

  let_it_be(:project) { create(:project, :public, :in_group, :with_duo_features_enabled) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  before do
    enable_ai_catalog
    stub_feature_flags(ai_catalog_unified_views: unified_views_enabled)
  end

  describe 'New agent' do
    before do
      sign_in(user)
      visit explore_ai_catalog_agents_path
    end

    shared_examples 'the New agent form' do
      it('fills form and submit') do
        expect(page).to have_css('h1', text: 'New agent')

        select_from_listbox project.name, from: 'Select a project'
        fill_in 'Display name', with: 'New agent name'
        fill_in 'Description', with: 'New agent description'
        fill_in 'System prompt', with: 'New system prompt'

        click_button 'Create agent'

        expect(page).to have_css('h1', text: 'New agent name')
        expect(page).to have_content('New agent description')
        expect(page).to have_content('New system prompt')
      end
    end

    context 'when ai_catalog_unified_views is disabled' do
      let(:unified_views_enabled) { false }

      before do
        click_link 'New agent'
      end

      it_behaves_like 'the New agent form'
    end

    context 'when ai_catalog_unified_views is enabled' do
      let(:unified_views_enabled) { true }

      before do
        within_testid('new-item-dropdown') do
          click_button 'Add'
          click_link 'Create agent'
        end
      end

      it_behaves_like 'the New agent form'
    end
  end
end
