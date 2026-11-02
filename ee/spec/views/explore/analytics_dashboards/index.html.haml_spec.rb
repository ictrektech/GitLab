# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'explore/analytics_dashboards/index.html.haml', feature_category: :custom_dashboards_foundation do
  using RSpec::Parameterized::TableSyntax

  it 'renders Vue app' do
    render

    expect(rendered).to have_selector('#js-explore-analytics-dashboards')
    expect(rendered).to have_selector('[data-explore-analytics-dashboards-path="/explore/analytics_dashboards"]')
    expect(view.content_for(:page_specific_styles)).to include('explore_analytics_dashboards')
  end

  describe 'data_source_clickhouse' do
    where(:clickhouse_enabled, :expected) do
      [[true, 'true'], [false, 'false']]
    end

    with_them do
      it 'reflects the instance-wide ClickHouse setting' do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?)
          .and_return(clickhouse_enabled)

        render

        expect(rendered).to have_selector(%([data-data-source-clickhouse="#{expected}"]))
      end
    end
  end

  describe 'gitlab_credits_dashboard_path' do
    it 'passes the GitLab Credits dashboard path when there is one' do
      allow(view).to receive(:explore_gitlab_credits_dashboard_path).and_return('/admin/gitlab_credits_dashboard')

      render

      expect(rendered).to have_selector('[data-gitlab-credits-dashboard-path="/admin/gitlab_credits_dashboard"]')
    end

    it 'leaves the path out when there is none' do
      allow(view).to receive(:explore_gitlab_credits_dashboard_path).and_return(nil)

      render

      expect(rendered).not_to have_selector('[data-gitlab-credits-dashboard-path]')
    end
  end

  it 'sets the page title' do
    allow(view).to receive(:page_title)

    render

    expect(view).to have_received(:page_title).with(s_('Analytics|GitLab Intelligence'))
  end
end
