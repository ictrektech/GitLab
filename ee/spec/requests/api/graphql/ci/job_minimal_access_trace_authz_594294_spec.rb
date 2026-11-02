# frozen_string_literal: true

require 'spec_helper'

# Regression / tripwire for security issue gitlab-org/gitlab#594294.
#
# A CiJobMinimalAccess viewer (here a read_admin_cicd custom admin role, which yields
# the minimal-access type rather than CiJob) must never receive a job trace. Today this
# is enforced by the inherited `trace` field's `:read_build` authorization, and, as
# defense-in-depth, by the `:read_build_trace` guard on JobMinimalAccessType#trace. If a
# future change exposes `trace` to minimal-access viewers, this test fails.
RSpec.describe 'Querying a CI job trace via CiJobMinimalAccess', :enable_admin_mode,
  feature_category: :continuous_integration do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private, :repository) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:build) { create(:ci_build, :trace_artifact, pipeline: pipeline) }
  let_it_be(:role) { create(:admin_member_role, :read_admin_cicd) }
  let_it_be(:current_user) { role.user }

  let(:query) do
    <<~GQL
      query {
        jobs {
          nodes { __typename trace { htmlSummary } }
        }
      }
    GQL
  end

  before_all do
    # Debug mode makes `:read_build_trace` require Developer+; the metadata-only viewer
    # lacks it, so the trace must be filtered out.
    create(:ci_job_variable, key: 'CI_DEBUG_TRACE', value: 'true', job: build)
  end

  before do
    stub_licensed_features(custom_roles: true)
  end

  it 'resolves the job as CiJobMinimalAccess and hides the debug-mode trace', :aggregate_failures do
    post_graphql(query, current_user: current_user)

    node = graphql_data_at(:jobs, :nodes, 0)

    expect(node['__typename']).to eq('CiJobMinimalAccess')
    expect(node['trace']).to be_nil
  end
end
