# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline details Integration (GraphQL fixtures)', type: :request,
  feature_category: :continuous_integration do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, path: 'pipeline-details-group') }
  let_it_be(:project, freeze: false) do
    create(:project, :repository, group: group, path: 'pipeline-details-project', developers: user)
  end

  let_it_be(:downstream_project) { create(:project, :repository, group: group, developers: user) }

  let_it_be_with_reload(:pipeline) do
    create(:ci_pipeline, name: 'Build pipeline', project: project, ref: 'master', sha: project.commit.id, user: user)
  end

  # Mirrors the 'pipeline builds' shared context of spec/features/projects/pipelines/pipeline_spec.rb
  let_it_be(:external_stage) { create(:ci_stage, name: 'external', pipeline: pipeline) }
  let_it_be(:build_passed) do
    create(:ci_build, :success, pipeline: pipeline, stage: 'build', stage_idx: 0, name: 'build-job')
  end

  let_it_be(:build_failed) do
    create(:ci_build, :failed, pipeline: pipeline, stage: 'test', stage_idx: 1, name: 'test-job')
  end

  let_it_be(:build_preparing) do
    create(:ci_build, :preparing, pipeline: pipeline, stage: 'deploy', stage_idx: 2, name: 'prepare-job')
  end

  let_it_be(:build_running) do
    create(:ci_build, :running, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'deploy-job')
  end

  let_it_be(:build_manual) do
    create(:ci_build, :manual, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'manual-job')
  end

  let_it_be(:build_scheduled) do
    create(:ci_build, :scheduled, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'delayed-job')
  end

  let_it_be(:build_external) do
    create(
      :generic_commit_status,
      status: 'success',
      pipeline: pipeline,
      name: 'jenkins-job',
      ci_stage: external_stage,
      ref: 'master',
      target_url: 'http://gitlab.com/status'
    )
  end

  let(:header_query) do
    get_graphql_query_as_string('ci/pipeline_details/header/graphql/queries/get_pipeline_header_data.query.graphql')
  end

  let(:details_query) do
    get_graphql_query_as_string('app/graphql/queries/pipelines/get_pipeline_details.query.graphql',
      with_base_path: false)
  end

  let(:jobs_query) do
    get_graphql_query_as_string('ci/pipeline_details/jobs/graphql/queries/get_pipeline_jobs.query.graphql')
  end

  # Retrying the pipeline runs 100 or 101 queries depending on whether an earlier example
  # warmed the protected-branch cache. The fixtures only record the response shape.
  let(:mutation_headers) do
    {
      'X-Gitlab-Disable-SQL-Query-Limit' =>
        '110,https://gitlab.com/gitlab-org/quality/analytics/ci-health-incidents/-/work_items/1446'
    }
  end

  base_output_path = 'graphql/ci/pipelines/integration/'
  mutations_path = 'ci/pipeline_details/graphql/mutations/'

  before do
    sign_in(user)
  end

  def record_header
    post_graphql(header_query, current_user: user, variables: { fullPath: project.full_path, iid: pipeline.iid.to_s })

    expect_graphql_errors_to_be_empty
  end

  def record_details
    post_graphql(details_query, current_user: user,
      variables: { projectPath: project.full_path, iid: pipeline.iid.to_s })

    expect_graphql_errors_to_be_empty
  end

  def record_jobs
    post_graphql(jobs_query, current_user: user, variables: { fullPath: project.full_path, iid: pipeline.iid.to_s })

    expect_graphql_errors_to_be_empty
  end

  def record_permissions
    query = get_graphql_query_as_string(
      'ci/pipeline_details/graph/graphql/queries/get_pipeline_permissions.query.graphql'
    )

    post_graphql(query, current_user: user, variables: { projectPath: project.full_path, iid: pipeline.iid.to_s })

    expect_graphql_errors_to_be_empty
  end

  def run_mutation(file, variables)
    post_graphql(get_graphql_query_as_string(file), current_user: user, variables: variables,
      headers: mutation_headers)

    expect_graphql_errors_to_be_empty
  end

  def header_status
    graphql_data_at(:project, :pipeline, :detailed_status, :text)
  end

  def graph_job(name)
    graphql_data_at(:project, :pipeline, :stages, :nodes)
      .flat_map { |stage| stage.dig('groups', 'nodes') }
      .flat_map { |group| group.dig('jobs', 'nodes') }
      .find { |job| job['name'] == name }
  end

  def downstream_node
    graphql_data_at(:project, :pipeline, :downstream, :nodes).first
  end

  describe GraphQL::Query do
    describe 'pipeline header' do
      it "#{base_output_path}get_pipeline_header_data.query.graphql.json" do
        record_header

        expect(header_status).to eq('Pending')
        expect(graphql_data_at(:project, :pipeline, :latest)).to be(true)
      end

      it "#{base_output_path}get_pipeline_header_data_after_job_retry.query.graphql.json", :sidekiq_inline do
        post retry_project_job_path(project, build_failed, format: :json)

        record_header

        expect(header_status).to eq('Running')
      end

      it "#{base_output_path}get_pipeline_header_data_after_job_play.query.graphql.json", :sidekiq_inline do
        post play_project_job_path(project, build_manual, format: :json)

        record_header

        expect(header_status).to eq('Running')
      end

      it "#{base_output_path}get_pipeline_header_data_after_pipeline_retry.query.graphql.json", :sidekiq_inline do
        run_mutation("#{mutations_path}retry_pipeline.mutation.graphql", { id: pipeline.to_global_id.to_s })

        record_header

        expect(header_status).to eq('Running')
        expect(graphql_data_at(:project, :pipeline, :retryable)).to be(false)
      end

      it "#{base_output_path}get_pipeline_header_data_after_pipeline_cancel.query.graphql.json", :sidekiq_inline do
        run_mutation("#{mutations_path}cancel_pipeline.mutation.graphql", { id: pipeline.to_global_id.to_s })

        record_header

        expect(graphql_data_at(:project, :pipeline, :cancelable)).to be(false)
      end

      it "#{base_output_path}get_pipeline_header_data_stuck.query.graphql.json" do
        create(:ci_build, :pending, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'stuck-job')

        record_header

        expect(graphql_data_at(:project, :pipeline, :stuck)).to be(true)
      end

      it "#{base_output_path}get_pipeline_header_data_config_error.query.graphql.json" do
        pipeline.update!(failure_reason: :config_error)
        pipeline.add_error_message('invalid YAML')
        pipeline.save!

        record_header

        expect(graphql_data_at(:project, :pipeline, :error_messages, :nodes, 0, :content)).to eq('invalid YAML')
      end

      it "#{base_output_path}get_pipeline_header_data_auto_devops.query.graphql.json" do
        pipeline.update!(config_source: :auto_devops_source)

        record_header

        expect(graphql_data_at(:project, :pipeline, :config_source)).to eq('AUTO_DEVOPS_SOURCE')
      end

      it "#{base_output_path}get_pipeline_header_data_detached_merge_request.query.graphql.json" do
        merge_request = create(:merge_request, source_project: project, source_branch: 'feature',
          target_project: project, target_branch: 'master')
        pipeline.update!(source: :merge_request_event, merge_request: merge_request)

        record_header

        expect(graphql_data_at(:project, :pipeline, :merge_request_event_type)).to eq('DETACHED')
      end

      it "#{base_output_path}get_duo_agent_sessions_on_pipeline.query.graphql.json" do
        query = get_graphql_query_as_string(
          'ai/shared/widgets/graphql/get_duo_agent_sessions_on_pipeline.query.graphql', ee: true
        )

        post_graphql(query, current_user: user,
          variables: { projectPath: project.full_path, iid: pipeline.iid.to_s })

        expect_graphql_errors_to_be_empty
      end
    end

    describe 'pipeline graph' do
      it "#{base_output_path}get_pipeline_details.query.graphql.json" do
        record_details

        expect(graph_job('test-job').dig('status', 'action', 'icon')).to eq('retry')
      end

      it "#{base_output_path}get_pipeline_details_after_failed_job_retry.query.graphql.json", :sidekiq_inline do
        post retry_project_job_path(project, build_failed, format: :json)

        record_details

        expect(graph_job('test-job').dig('status', 'action', 'icon')).to eq('cancel')
      end

      it "#{base_output_path}get_pipeline_details_after_running_job_cancel.query.graphql.json", :sidekiq_inline do
        post cancel_project_job_path(project, build_running, format: :json)

        record_details

        expect(graph_job('deploy-job').dig('status', 'action', 'icon')).to eq('retry')
      end

      it "#{base_output_path}get_pipeline_details_after_manual_job_play.query.graphql.json", :sidekiq_inline do
        post play_project_job_path(project, build_manual, format: :json)

        record_details

        expect(graph_job('manual-job').dig('status', 'action', 'icon')).to eq('cancel')
      end

      it "#{base_output_path}get_pipeline_details_after_delayed_job_unschedule.query.graphql.json" do
        post unschedule_project_job_path(project, build_scheduled, format: :json)

        record_details

        expect(graph_job('delayed-job').dig('status', 'action', 'icon')).to eq('play')
      end

      # Every downstream capture shares one record, so the graph and permissions queries agree on its id.
      context 'with a downstream pipeline' do
        let_it_be_with_reload(:downstream) do
          create(:ci_pipeline, :success, user: user, project: downstream_project, ref: 'master',
            sha: downstream_project.commit.id, child_of: pipeline)
        end

        let_it_be_with_reload(:downstream_build) do
          create(:ci_build, :success, pipeline: downstream, user: user)
        end

        def update_downstream_status(status)
          downstream_build.update_column(:status, status)
          downstream.update_column(:status, status)
        end

        it "#{base_output_path}get_pipeline_details_downstream_success.query.graphql.json" do
          record_details

          expect(downstream_node).to include('retryable' => false, 'cancelable' => false)
        end

        it "#{base_output_path}get_pipeline_details_downstream_running.query.graphql.json" do
          update_downstream_status(:running)

          record_details

          expect(downstream_node).to include('cancelable' => true)
        end

        it "#{base_output_path}get_pipeline_details_downstream_after_cancel.query.graphql.json", :sidekiq_inline do
          update_downstream_status(:running)
          run_mutation("#{mutations_path}cancel_pipeline.mutation.graphql", { id: downstream.to_global_id.to_s })

          record_details

          expect(downstream_node).to include('retryable' => true, 'cancelable' => false)
        end

        it "#{base_output_path}get_pipeline_details_downstream_failed.query.graphql.json" do
          update_downstream_status(:failed)

          record_details

          expect(downstream_node).to include('retryable' => true)
        end

        it "#{base_output_path}get_pipeline_details_downstream_after_retry.query.graphql.json", :sidekiq_inline do
          update_downstream_status(:failed)
          run_mutation("#{mutations_path}retry_pipeline.mutation.graphql", { id: downstream.to_global_id.to_s })

          record_details

          expect(downstream_node).to include('cancelable' => true)
        end

        it "#{base_output_path}get_pipeline_permissions_downstream.query.graphql.json" do
          record_permissions

          expect(graphql_data_at(:project, :pipeline, :downstream, :nodes, 0, :user_permissions, :update_pipeline))
            .to be(true)
        end
      end

      it "#{base_output_path}get_pipeline_permissions.query.graphql.json" do
        record_permissions

        expect(graphql_data_at(:project, :pipeline, :user_permissions, :update_pipeline)).to be(true)
      end
    end

    describe 'jobs tab' do
      it "#{base_output_path}get_pipeline_jobs.query.graphql.json" do
        record_jobs

        expect(graphql_data_at(:project, :pipeline, :jobs, :nodes, :name)).to include('delayed-job')
      end

      it "#{base_output_path}get_pipeline_jobs_after_unschedule.query.graphql.json" do
        run_mutation('ci/jobs_page/graphql/mutations/job_unschedule.mutation.graphql',
          { id: build_scheduled.to_global_id.to_s })

        record_jobs

        delayed_job = graphql_data_at(:project, :pipeline, :jobs, :nodes).find { |job| job['name'] == 'delayed-job' }
        expect(delayed_job['status']).to eq('MANUAL')
      end
    end
  end

  describe 'mutations' do
    it "#{base_output_path}retry_pipeline.mutation.graphql.json" do
      run_mutation("#{mutations_path}retry_pipeline.mutation.graphql", { id: pipeline.to_global_id.to_s })

      expect(graphql_data_at(:pipeline_retry, :errors)).to be_empty
    end

    it "#{base_output_path}cancel_pipeline.mutation.graphql.json" do
      run_mutation("#{mutations_path}cancel_pipeline.mutation.graphql", { id: pipeline.to_global_id.to_s })

      expect(graphql_data_at(:pipeline_cancel, :errors)).to be_empty
    end

    it "#{base_output_path}unschedule_job.mutation.graphql.json" do
      run_mutation('ci/jobs_page/graphql/mutations/job_unschedule.mutation.graphql',
        { id: build_scheduled.to_global_id.to_s })

      expect(graphql_data_at(:job_unschedule, :errors)).to be_empty
    end
  end

  describe 'REST endpoints' do
    let_it_be(:test_report_pipeline) do
      create(:ci_pipeline, :with_test_reports, :with_report_results, project: project)
    end

    it "#{base_output_path}test_report_summary.json" do
      get summary_project_pipeline_tests_path(project, test_report_pipeline, format: :json)

      expect(response).to be_successful
      expect(json_response.dig('total', 'count')).to be > 0
    end
  end
end
