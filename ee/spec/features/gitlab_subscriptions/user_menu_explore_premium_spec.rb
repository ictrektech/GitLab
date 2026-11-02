# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Explore Premium request modal in user menu', :saas_gitlab_com_subscriptions, :js,
  feature_category: :acquisition do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group_with_plan, plan: :free_plan, maintainers: user) }

  let(:heading) { s_('ExplorePremium|Get more from GitLab') }
  let(:learn_more_text) { _('Learn more') }
  let(:request_button_text) { s_('ExplorePremium|Request Premium features') }
  let(:requested_button_text) { s_('ExplorePremium|Interest recorded') }
  let(:explore_body_text) do
    s_('ExplorePremium|Premium adds more control over reviews, planning, and delivery. ' \
      'Explore what it has to offer for your group.')
  end

  let(:supporting_text) do
    s_("ExplorePremium|Thank you for your interest. Your group Owner isn't notified, " \
      'so ask them directly to upgrade.')
  end

  def open_explore_premium_modal
    find_by_testid('user-dropdown').click

    within_testid('user-dropdown') do
      click_button s_('ExplorePremium|Explore Premium')
    end
  end

  it 'transitions from not requested, to requested, to previously requested across sign-ins' do
    gitlab_sign_in(user)
    visit group_path(group)

    open_explore_premium_modal

    within_testid('explore-premium-modal') do
      expect(page).to have_content(heading)
      expect(page).to have_link(learn_more_text)
      expect(page).to have_button(request_button_text)
      expect(page).to have_no_content(supporting_text)

      click_button request_button_text

      # aria-disabled, not the disabled attribute (see explore_premium_modal.vue), so bypass the disabled filter.
      expect(page).to have_button(requested_button_text, disabled: :all)
      expect(page).to have_content(supporting_text)
    end

    # No visible UI signals when the async request-persistence call resolves; wait for the session
    # cookie, which is written once the POST succeeds (the DB row alone can land before it).
    wait_for('explore premium request persisted') do
      page.evaluate_script('document.cookie').include?("painted_door_explore_premium_request_painted_door_#{group.id}=")
    end

    page.refresh
    open_explore_premium_modal

    within_testid('explore-premium-modal') do
      expect(page).to have_button(requested_button_text, disabled: :all)
      expect(page).to have_content(supporting_text)
    end

    # Revisit the page so the open modal doesn't intercept the sign-out click below.
    visit group_path(group)
    gitlab_sign_out(user)
    gitlab_sign_in(user)
    visit group_path(group)

    open_explore_premium_modal

    within_testid('explore-premium-modal') do
      expect(page).to have_link(learn_more_text)
      expect(page).to have_no_button(requested_button_text)
      expect(page).to have_no_button(request_button_text)
      expect(page).to have_no_content(supporting_text)
      expect(page).to have_content(explore_body_text)
    end
  end
end
