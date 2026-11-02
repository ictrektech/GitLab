# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User closes a blocked incident', :js, feature_category: :incident_management do
  include Spec::Support::Helpers::ModalHelpers

  let_it_be(:project) { create(:project_empty_repo, :public) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:blocking_issue) { create(:issue, project: project) }
  let_it_be_with_reload(:incident) { create(:incident, project: project) }

  before_all do
    create(:issue_link, source: blocking_issue, target: incident, link_type: IssueLink::TYPE_BLOCKS)
  end

  before do
    stub_feature_flags(hide_incident_management_features: false)
    sign_in(user)

    visit incident_project_issues_path(project, incident)
  end

  it 'asks for confirmation in the header and closes the incident', :aggregate_failures do
    within_testid('issue-header') do
      find_by_testid('desktop-dropdown').click
    end
    within_testid('toggle-issue-state-button') do
      click_button 'Close incident'
    end

    expect(page).to have_css("#{Spec::Support::Helpers::ModalHelpers::MODAL_SELECTOR}.show")

    within_modal do
      expect(page).to have_css('h2', text: 'Are you sure you want to close this blocked issue?')
      expect(page).to have_link("##{blocking_issue.iid}")

      click_button 'Yes, close issue'
    end

    expect(page).to have_css('[data-testid="issue-state-badge"]', text: 'Closed')
    expect(page).not_to have_selector(Spec::Support::Helpers::ModalHelpers::MODAL_SELECTOR)
  end
end
