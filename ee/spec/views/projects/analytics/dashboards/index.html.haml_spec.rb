# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/analytics/dashboards/index',
  :aggregate_failures, feature_category: :value_stream_management do
  let_it_be(:group) { build(:group) }
  let_it_be(:project) { build(:project, :public, group: group) }

  before do
    stub_licensed_features(project_level_analytics_dashboard: true)

    assign(:project, project)
  end

  it 'renders the dashboards list app' do
    render

    expect(rendered).to have_selector('#js-analytics-dashboards-list-app')
    expect(rendered).to have_css("[data-namespace-full-path='#{project.full_path}']")
    expect(view.content_for(:page_specific_styles)).to include('page_bundles/analytics_dashboards')
    expect(view.content_for(:page_specific_styles)).not_to include('explore_analytics_dashboards')
  end
end
