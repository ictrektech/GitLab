# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/reporting/show' do
  let(:allowlist) { build_stubbed_list(:user, 2).map(&:username) }
  let(:alertlist) { build_stubbed_list(:user, 2).map(&:id) }
  let(:namespace_settings) do
    build_stubbed(
      :namespace_settings,
      unique_project_download_limit: 1,
      unique_project_download_limit_interval_in_seconds: 2,
      unique_project_download_limit_allowlist: allowlist,
      unique_project_download_limit_alertlist: alertlist,
      auto_ban_user_on_excessive_projects_download: true
    )
  end

  let(:group) { build_stubbed(:group, namespace_settings: namespace_settings) }

  before do
    allow(group).to receive(:unique_project_download_limit_enabled?).and_return(true)

    assign(:group, group)
  end

  it 'renders the settings app root with the correct data attributes', :aggregate_failures do
    render

    expect(rendered).to have_selector('#js-unique-project-download-limit-settings-form')

    expect(rendered).to have_selector("[data-group-full-path='#{group.full_path}']")
    expect(rendered).to have_selector('[data-max-number-of-repository-downloads="1"]')
    expect(rendered).to have_selector('[data-max-number-of-repository-downloads-within-time-period="2"]')
    expect(rendered).to have_selector("[data-git-rate-limit-users-allowlist='#{allowlist}']")
    expect(rendered).to have_selector("[data-git-rate-limit-users-alertlist='#{alertlist}']")
    expect(rendered).to have_selector("[data-auto-ban-user-on-excessive-projects-download='true']")
  end

  context 'when group has no settings record' do
    let(:group) { build_stubbed(:group) }

    it 'renders the settings app root with the correct data attributes containing default values',
      :aggregate_failures do
      render

      expect(rendered).to have_selector('#js-unique-project-download-limit-settings-form')

      expect(rendered).to have_selector('[data-max-number-of-repository-downloads="0"]')
      expect(rendered).to have_selector('[data-max-number-of-repository-downloads-within-time-period="0"]')
      expect(rendered).to have_selector("[data-git-rate-limit-users-allowlist='[]']")
      expect(rendered).to have_selector("[data-git-rate-limit-users-alertlist='[]']")
      expect(rendered).to have_selector("[data-auto-ban-user-on-excessive-projects-download='false']")
    end
  end

  context 'when feature is not enabled for the group' do
    before do
      allow(group).to receive(:unique_project_download_limit_enabled?).and_return(false)
    end

    it 'does not render the settings app root' do
      render

      expect(rendered).not_to have_selector('#js-unique-project-download-limit-settings-form')
    end
  end
end
