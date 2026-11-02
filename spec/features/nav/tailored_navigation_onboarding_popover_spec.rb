# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tailored navigation onboarding popover', :js, feature_category: :navigation do
  # Refind: sign_in hands this object to the server, and User memoizes callouts,
  # which reload doesn't clear.
  let_it_be_with_refind(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }
  let_it_be(:project) { create(:project, group: group, developers: user) }

  let(:popover_selector) { '[data-testid="tailored-navigation-onboarding-popover"]' }

  before do
    sign_in(user)
  end

  context 'when hide_unpinned_sidebar_items is enabled' do
    before do
      # Overrides the global stub in spec_helper.rb (hide_unpinned_sidebar_items: false)
      # to test the enabled state.
      stub_feature_flags(hide_unpinned_sidebar_items: true)
    end

    it 'shows the popover on the first visit to a project page' do
      visit project_path(project)

      expect(page).to have_css(popover_selector)
      expect(page).to have_content('Tailor your sidebar experience')
    end

    it 'shows the popover on the first visit to a group page' do
      visit group_path(group)

      expect(page).to have_css(popover_selector)
    end

    it 'walks through the layout step to the feature catalog step' do
      visit project_path(project)

      within popover_selector do
        expect(page).to have_content('Step 1 of 2')
      end

      expect(page).to be_axe_clean.within(popover_selector)

      within popover_selector do
        click_button s_('TailoredNav|Next')

        expect(page).to have_content(
          s_('TailoredNav|Explore and pin more features at any time from the Feature catalog.')
        )
      end

      expect(page).to be_axe_clean.within(popover_selector)
    end

    context 'when the user has pinned items of their own' do
      before do
        user.update!(pinned_nav_items: { 'project' => %w[pipelines] })
      end

      it 'shows the missing defaults after their pins without saving them', :aggregate_failures do
        visit project_path(project)

        expect(page).to have_css(popover_selector)
        within_testid 'pinned-nav-items' do
          expect(page).to have_link 'Pipelines'
          expect(page).to have_link 'Members'
        end
        expect(user.reload.pinned_nav_items).to eq('project' => %w[pipelines])
      end
    end

    it 'can be used and closed with the keyboard' do
      visit project_path(project)

      expect(page).to have_css("#{popover_selector}:focus")

      page.send_keys(:tab)

      expect(page).to have_css("#{popover_selector} [data-testid='close-button']:focus")

      find_button(s_('TailoredNav|Next')).send_keys(:enter)

      expect(page).to have_css("#{popover_selector}:focus", text: 'Step 2 of 2')

      page.send_keys(:escape)

      expect(page).to have_no_css(popover_selector)
      expect(page).to have_css('#super-sidebar-feature-library-trigger:focus')
    end

    it 'records the dismissal when the popover is closed' do
      visit project_path(project)

      within popover_selector do
        click_button 'Close'
      end

      expect(page).to have_no_css(popover_selector)

      # The popover hides before the dismiss mutation resolves, so poll for the record.
      wait_for('tailored navigation onboarding callout', polling_interval: 0.1) do
        user.callouts.exists?(feature_name: :tailored_navigation_onboarding)
      end
    end

    context 'when the user has already dismissed the popover' do
      before do
        create(:callout, feature_name: :tailored_navigation_onboarding, user: user)
      end

      it 'does not show the popover' do
        visit project_path(project)

        expect(page).to have_css('#super-sidebar-preferences-toggle')
        expect(page).to have_no_css(popover_selector)
      end
    end
  end

  context 'when hide_unpinned_sidebar_items is disabled' do
    before do
      stub_feature_flags(hide_unpinned_sidebar_items: false)
    end

    it 'does not show the popover' do
      visit project_path(project)

      expect(page).to have_css('#super-sidebar')
      expect(page).to have_no_css(popover_selector)
    end
  end
end
