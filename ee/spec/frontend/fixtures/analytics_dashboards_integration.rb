# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Explore analytics dashboards Integration (GraphQL fixtures)', type: :request,
  feature_category: :custom_dashboards_foundation do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, organizations: [organization]) }
  let_it_be(:other_user) { create(:user, organizations: [organization]) }

  # Pinned: the GLQL fixtures are keyed by queries that embed this path.
  let_it_be(:group) do
    create(:group, organization: organization, path: 'dap-impact-group', name: 'DAP Impact group')
  end

  # A group the user isn't in, so the flag can be on for someone else only.
  let_it_be(:other_group) { create(:group, organization: organization) }

  let_it_be(:alpha_project) { create(:project, group: group, path: 'dap-alpha') }
  let_it_be(:beta_project) { create(:project, group: group, path: 'dap-beta') }

  # The credits metrics also need the :read_agent_artifacts custom ability.
  let_it_be(:member_role) { create(:member_role, :reporter, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) do
    create(:group_member, :reporter, member_role: member_role, user: user, group: group)
  end

  let(:graphql_path) { 'explore/analytics_dashboards/graphql/' }
  let(:dashboard_slug) { 'dap_impact' }

  base_output_path = 'graphql/explore/analytics_dashboards/integration/'

  before do
    stub_current_organization(organization)
  end

  def post_system_dashboard_query
    query = get_graphql_query_as_string("#{graphql_path}get_system_dashboard.query.graphql")

    post_graphql(query, current_user: user, variables: { slug: dashboard_slug })
  end

  def system_dashboard
    graphql_data_at(:custom_system_dashboard)
  end

  def post_scope_namespace_query
    query = get_graphql_query_as_string("#{graphql_path}get_scope_namespace.query.graphql")

    post_graphql(query, current_user: user, variables: { fullPath: group.full_path, fullPaths: [group.full_path] })

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:group, :full_path)).to eq(group.full_path)
  end

  def expect_dashboard_not_available
    expect(system_dashboard).to be_nil
    expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
  end

  def listed_slugs
    query = get_graphql_query_as_string("#{graphql_path}get_dashboards.query.graphql")

    post_graphql(query, current_user: user)

    expect_graphql_errors_to_be_empty

    graphql_data_at(:custom_dashboards, :nodes).pluck('slug')
  end

  describe GraphQL::Query do
    # Grants the AI analytics permissions and the Duo Agent Platform the DAP Impact scope filter
    # requires.
    before do
      stub_licensed_features(ai_analytics: true)
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(true)
    end

    it "#{base_output_path}get_system_dashboard.query.graphql.json" do
      post_system_dashboard_query

      expect_graphql_errors_to_be_empty
      expect(system_dashboard).to include('slug' => dashboard_slug)
    end

    it "#{base_output_path}get_system_dashboard_feature_flag_disabled.query.graphql.json" do
      stub_feature_flags(dap_impact_v1: false)

      post_system_dashboard_query

      expect_dashboard_not_available
    end

    it "#{base_output_path}get_system_dashboard_in_group.query.graphql.json" do
      stub_feature_flags(dap_impact_v1: group)

      post_system_dashboard_query

      expect_graphql_errors_to_be_empty
      expect(system_dashboard).to include('slug' => dashboard_slug)
    end

    it "#{base_output_path}get_system_dashboard_not_in_group.query.graphql.json" do
      stub_feature_flags(dap_impact_v1: other_group)

      post_system_dashboard_query

      expect_dashboard_not_available
    end

    # Duo and SDLC trends is listed either way, so a missing DAP Impact isn't just an empty list.
    context 'when listing dashboards' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      end

      it "#{base_output_path}get_dashboards.query.graphql.json" do
        expect(listed_slugs).to include('duo_and_sdlc_trends', dashboard_slug)
      end

      it "#{base_output_path}get_dashboards_feature_flag_disabled.query.graphql.json" do
        stub_feature_flags(dap_impact_v1: false)

        expect(listed_slugs).to include('duo_and_sdlc_trends').and exclude(dashboard_slug)
      end

      it "#{base_output_path}get_dashboards_not_in_group.query.graphql.json" do
        stub_feature_flags(dap_impact_v1: other_group)

        expect(listed_slugs).to include('duo_and_sdlc_trends').and exclude(dashboard_slug)
      end
    end

    # A user with no visit history, so the scope picker derives no default scope and the
    # dashboard waits for a group or project to be picked.
    it "#{base_output_path}get_analytics_dashboard_frecent_groups.query.graphql.json" do
      query = get_graphql_query_as_string("#{graphql_path}get_frecent_groups.query.graphql")

      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:frecent_groups)).to be_empty
    end

    it "#{base_output_path}get_analytics_dashboard_top_level_groups.query.graphql.json" do
      query = get_graphql_query_as_string("#{graphql_path}get_top_level_groups.query.graphql")

      post_graphql(query, current_user: user, variables: { after: nil })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:groups, :nodes)).to contain_exactly(a_hash_including('fullPath' => group.full_path))
    end

    describe 'Duo Agent Platform top-level groups' do
      let(:query) do
        get_graphql_query_as_string("#{graphql_path}get_duo_agent_platform_top_level_groups.query.graphql", ee: true)
      end

      it "#{base_output_path}get_analytics_dashboard_duo_agent_platform_top_level_groups.query.graphql.json" do
        post_graphql(query, current_user: user, variables: { after: nil })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:groups, :nodes)).to contain_exactly(
          a_hash_including(
            'fullPath' => group.full_path,
            'userPermissions' => a_hash_including('readEnterpriseAiAnalytics' => true)
          )
        )
      end

      it "#{base_output_path}get_analytics_dashboard_duo_agent_platform_top_level_groups_none_qualifying" \
        ".query.graphql.json" do
        allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(false)

        post_graphql(query, current_user: user, variables: { after: nil })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:groups, :nodes)).to be_empty
      end
    end

    it "#{base_output_path}get_analytics_dashboard_duo_agent_platform_groups.query.graphql.json" do
      query = get_graphql_query_as_string("#{graphql_path}get_duo_agent_platform_groups.query.graphql", ee: true)

      post_graphql(query, current_user: user, variables: { ids: [group.to_global_id.to_s] })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:groups, :nodes)).to contain_exactly(a_hash_including('id' => group.to_global_id.to_s))
    end

    it "#{base_output_path}get_analytics_dashboard_scope_namespace.query.graphql.json" do
      post_scope_namespace_query

      expect(graphql_data_at(:group, :user_permissions, :read_pro_ai_analytics)).to be(true)
    end

    it "#{base_output_path}get_analytics_dashboard_scope_namespace_no_analytics_permission.query.graphql.json" do
      stub_licensed_features(ai_analytics: false)

      post_scope_namespace_query

      expect(graphql_data_at(:group, :user_permissions, :read_pro_ai_analytics)).to be(false)
    end
  end

  # The frontend and backend share the GLQL compiler, so compiling each panel here produces the
  # exact query the browser sends to /api/glql.
  describe 'DAP Impact GLQL panels', :click_house do
    include ClickHouseHelpers

    # Must match the date range the panel specs put in the URL.
    let(:current_period) { { 'startDate' => '2020-06-01', 'endDate' => '2020-06-30' } }
    let(:previous_period) { { 'startDate' => '2020-05-02', 'endDate' => '2020-05-31' } }
    let(:range_variables) do
      { 'dynamicGranularity' => 'daily', 'rangeDays' => '30', 'previousStartDate' => '2020-05-02' }
    end

    let(:statuses) { ::Ai::DuoWorkflows::Workflow.state_machines[:status].states }
    let(:glql_fixture) { {} }

    # The previous period's session gives the trend tiles a baseline.
    let(:flows_data) do
      [
        { id: 1, user_id: user.id, project: alpha_project, workflow_definition: 'chat',
          status: statuses[:finished].value, created_at: Time.utc(2020, 6, 5), credits_used: 1.5,
          created_merge_request_ids: [101], later_merged_merge_request_ids: [101] },
        { id: 2, user_id: user.id, project: beta_project, workflow_definition: 'software_development',
          status: statuses[:finished].value, created_at: Time.utc(2020, 6, 10), credits_used: 2.5,
          created_merge_request_ids: [102], later_merged_merge_request_ids: [102] },
        { id: 3, user_id: other_user.id, project: alpha_project, workflow_definition: 'fix_pipeline',
          status: statuses[:failed].value, created_at: Time.utc(2020, 6, 20), credits_used: 4.0 },
        { id: 4, user_id: user.id, project: alpha_project, workflow_definition: 'chat',
          status: statuses[:finished].value, created_at: Time.utc(2020, 5, 15), credits_used: 1.0 }
      ]
    end

    before do
      stub_licensed_features(
        ai_analytics: true,
        custom_roles: true,
        cycle_analytics_for_groups: true,
        group_level_compliance_dashboard: true,
        project_level_compliance_dashboard: true
      )
      allow(Gitlab::ClickHouse).to receive_messages(globally_enabled_for_analytics?: true, siphon_enabled?: true)

      clickhouse_fixture(:duo_workflows_workflows_enriched, flows_data.map do |flow|
        {
          id: flow[:id],
          user_id: flow[:user_id],
          project_id: flow[:project].id,
          workflow_definition: flow[:workflow_definition],
          status: flow[:status],
          model_used: 'claude-sonnet-4-5',
          created_at: flow[:created_at],
          updated_at: flow[:created_at],
          traversal_path: flow[:project].project_namespace.traversal_path(with_organization: true).to_s,
          credits_used: flow[:credits_used],
          created_merge_request_ids: Arel.sql("[#{flow.fetch(:created_merge_request_ids, []).join(', ')}]"),
          later_merged_merge_request_ids: Arel.sql("[#{flow.fetch(:later_merged_merge_request_ids, []).join(', ')}]"),
          later_closed_merge_request_ids: Arel.sql('[]'),
          _siphon_deleted: false,
          _version: flow[:created_at]
        }
      end)

      sign_in(user)
    end

    # The fixture helper stores `response` after the example; this fixture is the whole map.
    def response
      glql_fixture[:body] || super
    end

    def dashboard_panels
      config = Analytics::CustomDashboards::SystemDashboardsLoader.find_by_slug('dap_impact').config

      config['views'].flat_map { |view| view['panels'] }.reject { |panel| panel.key?('section') }
    end

    def interpolate(glql, variables)
      variables.reduce(glql) { |query, (name, value)| query.gsub("%{#{name}}", value) }
    end

    def uses_whole_date_range?(glql)
      %w[startDate endDate].all? { |name| glql.include?("%{#{name}}") }
    end

    # A panel with a `dateField` gets the range as a binding rather than placeholders in its query.
    def date_binding(period, date_field)
      return unless date_field

      {
        target: { kind: 'filter', field: date_field },
        value: { kind: 'range', from: period['startDate'], to: period['endDate'] }
      }
    end

    # Mirrors glql/core/parser.js.
    def compile_panel_query(glql_yaml, date_binding)
      config = YAML.safe_load(glql_yaml)
      query = config.delete('query')
      config['display'] ||= 'list'
      config['bindings'] = [
        { target: { kind: 'filter', field: 'group' }, value: { kind: 'list', values: [group.full_path] } },
        date_binding
      ].compact

      compiled = ::Glql.compile(query, config.merge(
        group: group.full_path,
        featureFlags: { glqlWorkItems: true, glqlCodeSuggestions: false }
      ))

      raise "GLQL failed to compile: #{compiled['output']}" unless compiled['success']

      compiled['output']
    end

    def panel_queries
      dashboard_panels.flat_map do |panel|
        glql = panel.dig('visualization', 'data', 'query', 'glql')
        date_field = panel.dig('visualization', 'data', 'query', 'dateField')
        queries = [[panel['title'], 'current', interpolate(glql, current_period.merge(range_variables)),
          date_binding(current_period, date_field)]]

        if panel.dig('visualization', 'options', 'showTrends')
          if date_field
            queries << [panel['title'], 'previous', interpolate(glql, range_variables),
              date_binding(previous_period, date_field)]
          elsif uses_whole_date_range?(glql)
            queries << [panel['title'], 'previous',
              interpolate(glql, previous_period.merge(range_variables.slice('dynamicGranularity')))]
          end
        end

        queries
      end
    end

    # Panels can share a query, so an entry names every panel that sends it.
    it "#{base_output_path}dap_impact_glql_responses.json" do
      responses = {}

      panel_queries.each do |title, period, glql_yaml, binding|
        compiled = compile_panel_query(glql_yaml, binding)

        if responses.key?(compiled)
          responses[compiled][:panels] |= [title]
          next
        end

        post '/api/glql', params: { query: compiled, operationName: 'GLQL', variables: { limit: 100 } }, as: :json

        expect(response).to have_gitlab_http_status(:ok), -> { "#{title} (#{period}): #{response.status}\n#{compiled}" }
        expect(json_response['errors']).to be_blank, -> { "#{title}: #{json_response['errors']}\n#{compiled}" }

        responses[compiled] = { panels: [title], period: period, response: json_response }
      end

      glql_fixture[:body] = Gitlab::Json.dump(responses)
    end
  end
end
