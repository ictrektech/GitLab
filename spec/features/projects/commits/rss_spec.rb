# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project Commits RSS', feature_category: :source_code_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, visibility_level: Gitlab::VisibilityLevel::PUBLIC) }
  let(:path) { project_commits_path(project, :master) }

  context 'when signed in', :js do
    before_all do
      project.add_developer(user)
    end

    before do
      sign_in(user)
      visit path
      click_button 'Actions'
    end

    it "shows the Commits feed link with current_user's feed token" do
      expect(page).to have_link 'Commits feed', href: /feed_token=glft-.*-#{user.id}/
    end

    it_behaves_like "an autodiscoverable RSS feed with current_user's feed token"
  end

  context 'when signed out', :js do
    before do
      visit path
      click_button 'Actions'
    end

    it 'shows the Commits feed link without a feed token' do
      expect(page).to have_link 'Commits feed'
      expect(page).not_to have_link 'Commits feed', href: /feed_token/
    end

    it_behaves_like "an autodiscoverable RSS feed without a feed token"
  end
end
