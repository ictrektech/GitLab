# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Explore > Analytics dashboards > System dashboards', :js, :with_current_organization,
  feature_category: :custom_dashboards_foundation do
  include ListboxHelpers
  include MobileHelpers

  let_it_be(:developer) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:owner) { create(:user) }
  let_it_be(:group) { create(:group, developers: developer, maintainers: maintainer, owners: owner) }

  let(:current_user) { developer }

  before do
    stub_licensed_features(product_analytics: true, ai_analytics: true)

    # The Duo dashboard is only offered with ClickHouse on. Some contexts turn it off.
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    # DAP Impact is only offered for groups with GitLab Duo Agent Platform on.
    allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(true)

    sign_in(current_user)
  end

  def select_group(group)
    find_button(s_('AnalyticsDashboards|Select a group or project')).click
    select_listbox_item(group.name)
    click_button _('Done')
  end

  describe 'GitLab Duo and SDLC trends' do
    # `let`, not `let_it_be`: the loader caches this object, and `let_it_be` would freeze it.
    let(:duo_dashboard) do
      Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('duo_and_sdlc_trends')
    end

    let(:dashboard_title) { duo_dashboard.config['title'] }

    # Titles with placeholders like `%{namespaceName}` are filled in at render time, so skip them.
    let(:panel_titles) { duo_dashboard.config['panels'].pluck('title').grep_v(/%\{/) }

    before do
      visit explore_analytics_dashboards_path
      click_link duo_dashboard.name
    end

    it 'routes to the dashboard by slug' do
      expect(page).to have_current_path(
        "#{explore_analytics_dashboards_path}/#{duo_dashboard.slug}",
        ignore_query: true
      )
    end

    it 'prompts for a namespace before rendering any panel', :aggregate_failures do
      expect(page).to have_content s_('AnalyticsDashboards|Select a group or project')
      expect(page).to have_no_content panel_titles.first
    end

    context 'when a group is selected' do
      before do
        select_group(group)
      end

      it_behaves_like 'a rendered analytics dashboard', date_range_filter: false

      # One example, since mounting every panel is the slow part.
      it 'replaces the empty state with the dashboard panels', :aggregate_failures do
        expect(page).to have_no_testid('no-namespace-empty-state')
        expect(page).to have_content dashboard_title
        expect(page).to have_content panel_titles.first
      end
    end

    context 'when ClickHouse is not enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)

        visit explore_analytics_dashboards_path
      end

      it 'does not offer the dashboard' do
        expect(page).to have_no_link duo_dashboard.name
      end
    end

    context 'when ClickHouse is enabled for analytics' do
      before do
        visit explore_analytics_dashboards_path
      end

      it 'offers the dashboard' do
        expect(page).to have_link duo_dashboard.name
      end
    end
  end

  describe 'DAP Impact' do
    let(:dap_dashboard) do
      Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('dap_impact')
    end

    # Only an owner can read credits, and only while the compliance dashboard is licensed.
    let(:current_user) { owner }
    let(:licensed_features) do
      {
        product_analytics: true,
        ai_analytics: true,
        cycle_analytics_for_groups: true,
        group_level_compliance_dashboard: true
      }
    end

    let(:unexpected_panel_states) { %w[no-access not-configured unavailable error error-no-retry] }

    # Panels that only show credits, which non-owners can't read.
    let(:restricted_access_panels) do
      {
        'Overview' => ['Credits consumed', 'Where credits went'],
        'Spend' => ['Credits by model, by capability', 'Credits', 'Chat', 'Credits over time']
      }
    end

    let(:unrestricted_panels) do
      {
        'Overview' => ['Active projects', 'Active users', 'Completed sessions'],
        'Spend' => []
      }
    end

    def view_titled(title)
      dap_dashboard.config['views'].find { |view| view['title'] == title }
    end

    # Matched on the title attribute, so "Credits" doesn't match "Credits over time". GLQL panels
    # have no visualization slug, so every panel's testid is just `panel-`.
    def panel_titled(title)
      find(%([data-testid="panel-title"] [title="#{title}"])).ancestor(%([data-testid="panel-"]))
    end

    # With no scope in the URL, DAP Impact selects the user's first qualifying group itself.
    def wait_for_default_group
      within_testid('dashboard-filters') { find_button(group.name) }
    end

    before do
      # Panels only query near the viewport, so make it tall enough for every panel to run.
      # See https://gitlab.com/gitlab-org/gitlab/-/merge_requests/258120.
      resize_window(1366, 3000)

      visit explore_analytics_dashboards_path
      click_link dap_dashboard.name
    end

    it 'routes to the dashboard by slug' do
      expect(page).to have_current_path(
        "#{explore_analytics_dashboards_path}/#{dap_dashboard.slug}",
        ignore_query: true
      )
    end

    context 'when a group is selected' do
      before do
        wait_for_default_group
      end

      # A new panel fails this until it's added to one of the panel lists.
      %w[Overview Spend].each do |view_title|
        it "renders every #{view_title} panel in the panel lists", :aggregate_failures do
          config_titles = view_titled(view_title)['panels'].reject { |panel| panel.key?('section') }.pluck('title')

          within_testid('dashboard-views') { click_link view_title }

          expect(restricted_access_panels[view_title] + unrestricted_panels[view_title]).to match_array(config_titles)
          expect(page).to have_testid('panel-', count: config_titles.size)
          config_titles.each { |title| expect(panel_titled(title)).to be_visible }
        end
      end

      # A developer can't read credits, so their run catches a mixed panel breaking for non-owners.
      [
        ['Adoption', 1, :owner],
        ['Work', 2, :owner],
        ['Spend', 3, :owner],
        ['Adoption', 1, :developer]
      ].each do |view_title, view_index, role|
        context "and the #{view_title} tab is selected as #{role}", :click_house do
          let(:current_user) { public_send(role) }
          let(:view) { dap_dashboard.config['views'][view_index] }
          # Sections have no visualization, so they're left out.
          let(:view_panels) { view['panels'].reject { |panel| panel.key?('section') } }
          let(:view_panel_titles) { view_panels.pluck('title') }

          # Data source panels have no GLQL query, so they're left out.
          let(:glql_queries) do
            view_panels.filter_map { |panel| panel.dig('visualization', 'data', 'query', 'glql') }
          end

          let(:glql_configs) { glql_queries.map { |glql| YAML.safe_load(glql) } }

          # Breakdown tiles have an empty description, so only the others are checked.
          let(:stat_descriptions) do
            glql_configs
              .select { |config| config['display'] == 'stat' }
              .filter_map { |config| config.dig('displayConfig', 'description').presence }
          end

          # With no data, GLQL panels with dimensions show the no-data state and data source panels
          # show their own empty state, so they're counted separately.
          let(:no_data_panel_count) do
            glql_configs.count { |config| config.key?('dimensions') }
          end

          let(:data_source_panel_count) { view_panels.size - glql_queries.size }

          # Queries run one at a time and trend comparisons queue last, so the last trend stat settles last.
          let(:last_trend_stat_description) do
            view_panels
              .select { |panel| panel.dig('visualization', 'options', 'showTrends') }
              .filter_map { |panel| panel.dig('visualization', 'data', 'query', 'glql') }
              .map { |glql| YAML.safe_load(glql) }
              .reverse
              .find { |config| config['display'] == 'stat' }
              .dig('displayConfig', 'description')
          end

          before do
            stub_licensed_features(**licensed_features)

            clickhouse_fixture(:siphon_internal_events,
              [{ postgresql_schema: 'public', postgresql_table: 'merge_requests' }])

            within_testid('dashboard-views') { click_link view['title'] }
          end

          # Wait for every panel to settle first, or the absence checks pass before an error shows up.
          it 'renders every panel without a GLQL error', :aggregate_failures do
            view_panel_titles.each { |title| expect(page).to have_content(title) }

            # Work runs 31 queries, so allow a long wait on the one that settles last.
            expect(page).to have_content(last_trend_stat_description, wait: 90)
            stat_descriptions.each { |description| expect(page).to have_content(description) }
            expect(page).to have_testid('panel-state-no-data', count: no_data_panel_count)
            expect(page).to have_content(
              s_('Analytics|No results match your query or filter.'), count: data_source_panel_count
            )
            unexpected_panel_states.each do |variant|
              expect(page).to have_no_testid("panel-state-#{variant}")
            end
          end
        end
      end
    end

    # Outside 'when a group is selected': licences must be stubbed before the panels load.
    context 'when a user who cannot read credits selects a group', :click_house do
      using RSpec::Parameterized::TableSyntax

      where(:role, :view_title, :compliance_dashboard) do
        :developer  | 'Overview' | true
        :developer  | 'Spend'    | true
        :maintainer | 'Overview' | true
        :maintainer | 'Spend'    | true
        :owner      | 'Overview' | false
        :owner      | 'Spend'    | false
      end

      with_them do
        let(:current_user) { public_send(role) }

        before do
          stub_licensed_features(**licensed_features, group_level_compliance_dashboard: compliance_dashboard)

          clickhouse_fixture(:siphon_internal_events,
            [{ postgresql_schema: 'public', postgresql_table: 'merge_requests' }])

          # The group was picked on load, before this setup, so reload to run every panel with it.
          page.refresh
          wait_for_default_group
          within_testid('dashboard-views') { click_link view_title }
        end

        it 'shows no access on the credits panels only', :aggregate_failures do
          # The no-access state only shows once the request fails, which can take
          # longer than Capybara's default wait on CI.
          restricted_access_panels[view_title].each do |title|
            expect(panel_titled(title)).to have_testid('panel-state-no-access', wait: 90)
          end
          expect(page).to have_testid('panel-state-no-access', count: restricted_access_panels[view_title].size)

          # Queries run in mount order, so the panels above the credits ones have settled by now.
          unrestricted_panels[view_title].each do |title|
            unexpected_panel_states.each do |variant|
              expect(panel_titled(title)).to have_no_testid("panel-state-#{variant}")
            end
          end
        end
      end
    end
  end

  # The MSW specs render responses recorded through this gate; only these check it end to end.
  describe 'DAP Impact feature flag' do
    let(:loader) { Analytics::CustomDashboards::SystemDashboardsLoader }
    let(:dap_dashboard_name) { loader.find_by_slug('dap_impact').name }

    shared_examples 'a hidden DAP Impact dashboard' do
      it 'is not offered and is not found by its slug', :aggregate_failures do
        visit explore_analytics_dashboards_path

        expect(page).to have_link(loader.find_by_slug('duo_and_sdlc_trends').name)
        expect(page).to have_no_link(dap_dashboard_name)

        visit "#{explore_analytics_dashboards_path}/dap_impact"

        expect(page).to have_testid('dashboard-not-found')
      end
    end

    context 'when it is disabled' do
      before do
        stub_feature_flags(dap_impact_v1: false)
      end

      it_behaves_like 'a hidden DAP Impact dashboard'
    end

    context 'when it is enabled for a root group' do
      before do
        stub_feature_flags(dap_impact_v1: group)
      end

      it 'is offered to a member, and opens from the list', :aggregate_failures do
        visit explore_analytics_dashboards_path
        click_link dap_dashboard_name

        expect(page).to have_current_path("#{explore_analytics_dashboards_path}/dap_impact", ignore_query: true)
        expect(page).to have_content s_('AnalyticsDashboards|Select a group or project')
        expect(page).to have_no_testid('dashboard-not-found')
      end

      context 'when the user is outside that group' do
        let(:current_user) { create(:user) }

        it_behaves_like 'a hidden DAP Impact dashboard'
      end
    end
  end
end
