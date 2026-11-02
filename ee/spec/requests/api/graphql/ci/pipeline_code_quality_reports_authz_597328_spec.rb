# frozen_string_literal: true

require 'spec_helper'

# Regression test for security issue gitlab-org/gitlab#597328.
# The GraphQL Pipeline.codeQualityReports / codeQualityReportSummary fields are
# gated only by read_pipeline on PipelineType and previously read the unscoped
# pipeline.codequality_reports. A Reporter could read maintainer-only artifact
# content via a plain pipeline query, no MR required. The fields must use the
# viewer-scoped #accessible_codequality_reports.
RSpec.describe 'Pipeline.codeQualityReports viewer authorization', feature_category: :code_quality do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private) }
  let(:query) do
    graphql_query_for('project', { fullPath: project.full_path },
      query_graphql_field('pipeline', { iid: pipeline.iid.to_s },
        query_graphql_field('codeQualityReports', {}, 'nodes { description }')))
  end

  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:pipeline) { create(:ci_pipeline, :success, project: project) }

  before_all do
    create(:ci_job_artifact, :codequality, :maintainer_only_access,
      job: create(:ci_build, :success, name: 'codequality', pipeline: pipeline))
  end

  def code_quality_nodes_for(user)
    post_graphql(query, current_user: user)
    graphql_data.dig('project', 'pipeline', 'codeQualityReports', 'nodes')
  end

  it 'hides maintainer-only degradations from a reporter' do
    expect(code_quality_nodes_for(reporter)).to be_blank
  end

  it 'exposes them to a user who can read the artifact' do
    expect(code_quality_nodes_for(maintainer)).to be_present
  end
end
