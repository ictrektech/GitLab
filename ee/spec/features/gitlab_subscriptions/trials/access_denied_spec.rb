# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ultimate trial access denied flow', :saas_trial, :js, feature_category: :acquisition do
  it 'signs in and experiences the entire access denied flow' do
    trial_path = new_trial_path(namespace_id: non_existing_record_id)

    gitlab_sign_in(:user)

    expect(page).to have_current_path(root_path)

    visit trial_path

    expect(page).to have_content('You do not have access to trial GitLab Duo To start a GitLab Duo trial')

    click_button 'Go back'

    expect(page).to have_current_path(root_path)

    visit trial_path

    click_button 'Sign in with a different account'

    expect(page).to have_current_path(new_user_session_path)
  end
end
