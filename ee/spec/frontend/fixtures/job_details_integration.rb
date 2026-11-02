# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Job details Integration (JavaScript fixtures)', type: :request, feature_category: :continuous_integration do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { create(:namespace, name: 'frontend-fixtures') }
  let_it_be(:project, freeze: false) do
    create(:project, :repository, namespace: namespace, path: 'job-details-project')
  end

  let_it_be(:pipeline) { create(:ci_pipeline, project: project, sha: project.commit.sha, ref: 'master') }
  let_it_be(:build) { create(:ci_build, :success, :trace_artifact, :coverage, pipeline: pipeline) }
  # Kept off `pipeline` so the recorded stage fixtures stay unchanged.
  let_it_be(:manual_pipeline) { create(:ci_pipeline, project: project, sha: project.commit.sha, ref: 'master') }
  let_it_be(:manual_build) { create(:ci_build, :manual, pipeline: manual_pipeline) }
  let_it_be(:manual_build_with_inputs) do
    create(:ci_build, :manual, pipeline: manual_pipeline, options: {
      inputs: {
        environment: { type: 'string', description: 'Target environment' },
        version: { type: 'string', default: '1.0' },
        debug: { type: 'boolean', default: false }
      }
    })
  end

  base_output_path = 'graphql/ci/job_details/integration/'

  before_all do
    project.update!(ci_pipeline_variables_minimum_override_role: :maintainer)
    project.add_maintainer(user)
    project.enable_ci
  end

  before do
    sign_in(user)
  end

  def get_stage_json
    get stage_project_pipeline_path(project, pipeline, format: :json), params: { stage: 'test', retried: 1 }
  end

  describe GraphQL::Query do
    it "#{base_output_path}get_job.query.graphql.json" do
      query = get_graphql_query_as_string('ci/job_details/graphql/queries/get_job.query.graphql')

      post_graphql(query, current_user: user, variables: { fullPath: project.full_path, id: build.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :job, :name)).to eq(build.name)
    end

    it "#{base_output_path}get_job_manual.query.graphql.json" do
      query = get_graphql_query_as_string('ci/job_details/graphql/queries/get_job.query.graphql')

      post_graphql(query, current_user: user, variables: { fullPath: project.full_path, id: manual_build_gid })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :job, :manual_job)).to be(true)
    end

    it "#{base_output_path}get_job_manual_with_inputs.query.graphql.json" do
      query = get_graphql_query_as_string('ci/job_details/graphql/queries/get_job.query.graphql')

      post_graphql(query, current_user: user,
        variables: { fullPath: project.full_path, id: manual_build_with_inputs.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :job, :inputs_spec, :name)).to include('environment')
    end

    it "#{base_output_path}get_job_inputs.query.graphql.json" do
      post_graphql(get_job_inputs_query, current_user: user,
        variables: { fullPath: project.full_path, id: manual_build_gid })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :job, :inputs_spec)).to be_empty
    end

    it "#{base_output_path}get_job_inputs_with_inputs.query.graphql.json" do
      post_graphql(get_job_inputs_query, current_user: user,
        variables: { fullPath: project.full_path, id: manual_build_with_inputs.to_global_id.to_s })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :job, :inputs_spec, :name)).to include('environment')
    end
  end

  describe GraphQL::Query, 'mutations' do
    it "#{base_output_path}play_job_with_inputs.mutation.graphql.json" do
      build_to_play = create(:ci_build, :manual, pipeline: manual_pipeline)

      post_graphql(play_job_with_inputs_mutation, current_user: user, variables: {
        id: build_to_play.to_global_id.to_s,
        variables: [{ key: 'key_name', value: 'key_value' }],
        inputs: []
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:job_play, :errors)).to be_empty
    end

    it "#{base_output_path}play_job_with_inputs_error.mutation.graphql.json" do
      post_graphql(play_job_with_inputs_mutation, current_user: user, variables: {
        id: manual_build_with_inputs.to_global_id.to_s,
        variables: [],
        inputs: [{ name: 'unknown_input', value: 'value' }]
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:job_play, :errors)).to include(match(/Unknown input/))
      expect(graphql_data_at(:job_play, :job)).to be_nil
    end
  end

  describe 'REST endpoints' do
    describe 'job' do
      it "#{base_output_path}job.json" do
        get project_job_path(project, build, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('has_trace' => true, 'erase_path' => erase_project_job_path(project, build))
      end

      # What Rails leaves behind after a real erase: no log, no artifacts, so no erase action.
      it "#{base_output_path}job_erased.json" do
        erased_build = create(:ci_build, :success, :erased, pipeline: pipeline)

        get project_job_path(project, erased_build, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('has_trace' => false)
        expect(json_response['erased_at']).to be_present
        expect(json_response).not_to have_key('erase_path')
      end

      it "#{base_output_path}job_no_trace.json" do
        no_trace_build = create(:ci_build, :success, :unarchived_trace_artifact, :coverage, pipeline: pipeline)

        get project_job_path(project, no_trace_build, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('has_trace' => false)
      end

      it "#{base_output_path}job_parallel.json" do
        parallel_build = create_parallel_build

        get project_job_path(project, parallel_build, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('has_trace' => true, 'test_suite_name' => 'rspec')
      end

      it "#{base_output_path}job_manual.json" do
        get project_job_path(project, manual_build, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('playable' => true, 'has_trace' => false)
      end

      it "#{base_output_path}job_manual_with_inputs.json" do
        get project_job_path(project, manual_build_with_inputs, format: :json)

        expect(response).to be_successful
        expect(json_response).to include('playable' => true, 'has_trace' => false)
      end

      it "#{base_output_path}job_failed.json" do
        failed_build = create(:ci_build, :failed, :trace_live, pipeline: pipeline)

        get project_job_path(project, failed_build, format: :json)

        expect(response).to be_successful
        expect(json_response.dig('status', 'group')).to eq('failed')
      end
    end

    it "#{base_output_path}trace.json" do
      get trace_project_job_path(project, build, format: :json)

      expect(response).to be_successful
      expect(json_response).to include('complete' => true)
      expect(json_response['lines']).to be_present
    end

    it "#{base_output_path}test_report_summary.json" do
      parallel_build = create_parallel_build

      get test_report_summary_project_job_path(project, parallel_build, format: :json)

      expect(response).to be_successful
    end

    describe 'stage' do
      it "#{base_output_path}stage.json" do
        get_stage_json

        expect(response).to be_successful
        expect(json_response['latest_statuses'].pluck('name')).to eq([build.name])
        expect(json_response['retried']).to eq([])
      end

      it "#{base_output_path}stage_failed.json" do
        create(:ci_build, :failed, :trace_live, pipeline: pipeline)

        get_stage_json

        expect(response).to be_successful
        expect(json_response['latest_statuses'].map { |job| job.dig('status', 'group') }).to include('failed')
      end

      it "#{base_output_path}stage_failed_retried.json" do
        create(:ci_build, :failed, :retried, :trace_artifact, pipeline: pipeline)

        get_stage_json

        expect(response).to be_successful
        expect(json_response['retried'].map { |job| job.dig('status', 'tooltip') }).to all(end_with('(retried)'))
        expect(json_response['retried']).not_to be_empty
      end
    end
  end

  def manual_build_gid
    manual_build.to_global_id.to_s
  end

  def get_job_inputs_query
    get_graphql_query_as_string('ci/job_details/graphql/queries/get_job_inputs.query.graphql')
  end

  def play_job_with_inputs_mutation
    get_graphql_query_as_string('ci/job_details/graphql/mutations/job_play_with_inputs.mutation.graphql')
  end

  def create_parallel_build
    create(:ci_build, :success, :report_results, :trace_artifact, name: 'rspec 1/2', pipeline: pipeline,
      options: { parallel: { number: 1, total: 2 } })
  end
end
