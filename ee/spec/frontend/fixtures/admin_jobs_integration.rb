# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin jobs Integration (GraphQL fixtures)', type: :request, feature_category: :continuous_integration do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers
  include AdminModeHelper

  let_it_be(:admin) { create(:admin) }
  let_it_be(:namespace) { create(:namespace, name: 'frontend-fixtures') }
  let_it_be(:project) { create(:project, namespace: namespace, path: 'admin-jobs-project') }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:runner) { create(:ci_runner, :instance) }

  # One job per status the admin table distinguishes: the All tab lists all four,
  # the Finished tab only the last two, and the Failed filter only the last one.
  let_it_be(:pending_job) { create(:ci_build, :pending, name: 'pending-job', pipeline: pipeline) }
  let_it_be(:running_job) { create(:ci_build, :running, name: 'running-job', pipeline: pipeline, runner: runner) }
  let_it_be(:success_job) { create(:ci_build, :success, name: 'success-job', pipeline: pipeline, runner: runner) }
  let_it_be(:failed_job) { create(:ci_build, :failed, name: 'failed-job', pipeline: pipeline) }

  base_output_path = 'graphql/ci/admin_jobs/integration/'
  queries_path = 'ci/admin/jobs_table/graphql/queries/'

  before do
    sign_in(admin)
    enable_admin_mode!(admin)
  end

  describe GraphQL::Query do
    let(:all_jobs_query) { get_graphql_query_as_string("#{queries_path}get_all_jobs.query.graphql") }
    let(:all_jobs_count_query) { get_graphql_query_as_string("#{queries_path}get_all_jobs_count.query.graphql") }

    let(:cancelable_jobs_count_query) do
      get_graphql_query_as_string("#{queries_path}get_cancelable_jobs_count.query.graphql")
    end

    def job_names
      graphql_data_at(:jobs, :nodes).pluck('name')
    end

    it "#{base_output_path}get_all_jobs.query.graphql.json" do
      post_graphql(all_jobs_query, current_user: admin)

      expect_graphql_errors_to_be_empty
      expect(job_names).to contain_exactly('pending-job', 'running-job', 'success-job', 'failed-job')
    end

    it "#{base_output_path}get_all_jobs_finished.query.graphql.json" do
      post_graphql(all_jobs_query, current_user: admin, variables: { statuses: %w[SUCCESS FAILED CANCELED] })

      expect_graphql_errors_to_be_empty
      expect(job_names).to contain_exactly('success-job', 'failed-job')
    end

    it "#{base_output_path}get_all_jobs_failed.query.graphql.json" do
      post_graphql(all_jobs_query, current_user: admin, variables: { statuses: %w[FAILED] })

      expect_graphql_errors_to_be_empty
      expect(job_names).to contain_exactly('failed-job')
    end

    it "#{base_output_path}get_all_jobs_count.query.graphql.json" do
      post_graphql(all_jobs_count_query, current_user: admin)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:jobs, :count)).to eq(4)
    end

    it "#{base_output_path}get_all_jobs_count_failed.query.graphql.json" do
      post_graphql(all_jobs_count_query, current_user: admin, variables: { statuses: %w[FAILED] })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:jobs, :count)).to eq(1)
    end

    it "#{base_output_path}get_cancelable_jobs_count.query.graphql.json" do
      post_graphql(cancelable_jobs_count_query, current_user: admin)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:cancelable, :count)).to eq(2)
    end
  end
end
