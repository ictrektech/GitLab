# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline security tab Integration (GraphQL fixtures)', type: :request,
  feature_category: :vulnerability_management do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository, developers: user) }
  let_it_be(:pipeline) { create(:ee_ci_pipeline, :success, :with_sast_report, project: project) }
  let_it_be(:scanner) { create(:vulnerabilities_scanner, project: project) }

  let_it_be(:security_scan) do
    create(:security_scan, :latest_successful, pipeline: pipeline, build: pipeline.builds.first, project: project)
  end

  let_it_be(:security_finding) do
    create(:security_finding, :with_finding_data, scanner: scanner, scan: security_scan, deduplicated: true)
  end

  base_output_path = 'graphql/ci/pipelines/integration/'
  queries_path = 'security_dashboard/graphql/queries/'
  findings_query = "#{queries_path}pipeline_findings.query.graphql"

  # Mirrors DEFAULT_PAGE_SIZE
  findings_variables = { first: 20, sort: 'severity_desc' }

  before do
    stub_licensed_features(security_dashboard: true, sast: true)
    sign_in(user)
  end

  describe GraphQL::Query do
    it "#{base_output_path}pipeline_security_summary.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}pipeline_security_report_summary.query.graphql", ee: true)

      post_graphql(query, current_user: user,
        variables: { fullPath: project.full_path, pipelineIid: pipeline.iid.to_s })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}enabled_scans.query.graphql.json" do
      query = get_graphql_query_as_string('vue_merge_request_widget/queries/enabled_scans.query.graphql', ee: true)

      post_graphql(query, current_user: user,
        variables: { fullPath: project.full_path, pipelineIid: pipeline.iid.to_s })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}pipeline_findings.query.graphql.json" do
      query = get_graphql_query_as_string(findings_query, ee: true)

      post_graphql(query, current_user: user,
        variables: { fullPath: project.full_path, pipelineId: pipeline.iid.to_s, **findings_variables })

      expect_graphql_errors_to_be_empty
    end
  end
end
