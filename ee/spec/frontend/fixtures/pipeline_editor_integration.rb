# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline editor Integration (GraphQL fixtures)', type: :request,
  feature_category: :pipeline_composition do
  include ApiHelpers
  include AdminModeHelper
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:project, freeze: false) { create(:project_empty_repo, :public, default_branch: 'main') }
  let_it_be(:user, freeze: false) { create(:user, developer_of: project) }
  let_it_be(:admin, freeze: false) { create(:admin) }

  valid_content = <<~YAML
    ---
    stages:
      - Build
      - Test
    job_a:
      script: echo hello
      stage: Build
    job_b:
      script: echo hello from job b
      stage: Test
  YAML

  invalid_content = <<~YAML

    job3:
    stage: stage_foo
    script: echo 'Done.'
  YAML

  content_with_broken_yaml = <<~YAML
    job_a:
      script: echo first
       misindented_key: echo second
  YAML

  before_all do
    project.repository.create_file(user, project.ci_config_path_or_default, 'Default',
      message: 'Create CI file for main', branch_name: 'main')
    project.repository.create_file(user, project.ci_config_path_or_default, valid_content,
      message: 'Create CI file for test', branch_name: 'test')
    project.repository.create_file(user, project.ci_config_path_or_default, invalid_content,
      message: 'Create CI file for test', branch_name: 'despair')
    project.repository.create_file(user, 'index.js', 'file', message: 'New js file', branch_name: 'empty')
    project.repository.create_file(user, project.ci_config_path_or_default, content_with_broken_yaml,
      message: 'Create CI file with broken YAML', branch_name: 'broken-yaml')
    Sidekiq::Worker.skipping_transaction_check { project.change_head('main') }
  end

  before do
    sign_in(user)
  end

  base_output_path = 'graphql/ci/pipeline_editor/integration/'

  describe GraphQL::Query do
    let_it_be(:main_pipeline) do
      create(:ci_pipeline, project: project, sha: project.commit('main').id, finished_at: 1.hour.ago)
    end

    {
      'get_blob_content_main' => 'main',
      'get_blob_content_valid' => 'test',
      'get_blob_content_invalid' => 'despair',
      'get_blob_content_empty' => 'empty',
      'get_blob_content_broken_yaml' => 'broken-yaml'
    }.each do |fixture_name, ref|
      it "#{base_output_path}#{fixture_name}.query.graphql.json" do
        query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/blob_content.query.graphql')

        post_graphql(query, current_user: user, variables: {
          projectPath: project.full_path,
          path: project.ci_config_path_or_default,
          ref: ref
        })

        expect_graphql_errors_to_be_empty
      end
    end

    it "#{base_output_path}get_latest_commit_sha.query.graphql.json" do
      query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/latest_commit_sha.query.graphql')

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path, ref: 'main' })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_pipeline_iid.query.graphql.json" do
      query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/get_pipeline_iid.query.graphql')
      commit = project.commit('main')

      post_graphql(query, current_user: user, variables: { fullPath: project.full_path, sha: commit.sha })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_pipeline_summary.query.graphql.json" do
      query = get_graphql_query_as_string(
        'ci/common/pipeline_summary/graphql/queries/get_pipeline_summary.query.graphql'
      )
      post_graphql(query, current_user: user, variables: {
        fullPath: project.full_path,
        iid: main_pipeline.iid,
        includeCommitInfo: true
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_available_branches.query.graphql.json" do
      query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/available_branches.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectFullPath: project.full_path,
        limit: 20,
        offset: 0,
        searchPattern: 'main*'
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('project', 'repository', 'branchNames')).to contain_exactly('main')
    end

    it "#{base_output_path}get_template.query.graphql.json" do
      query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/get_starter_template.query.graphql')

      post_graphql(query, current_user: user, variables: {
        projectPath: project.full_path,
        templateName: 'Getting-Started'
      })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_runner_tags.query.graphql.json" do
      query = get_graphql_query_as_string('ci/pipeline_editor/graphql/queries/runner_tags.query.graphql')
      sign_in(admin)
      enable_admin_mode!(admin)

      post_graphql(query, current_user: admin)

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'lint mutations' do
    {
      'ci_lint_valid' => [valid_content, 'test', false],
      'ci_lint_invalid' => [invalid_content, 'despair', false],
      'ci_lint_main' => ['Default', 'main', false],
      'ci_lint_template' => [Gitlab::Template::GitlabCiYmlTemplate.find('Getting-Started').content, 'empty', false],
      'ci_lint_valid_dry_run' => [valid_content, 'test', true],
      'ci_lint_invalid_dry_run' => [invalid_content, 'despair', true]
    }.each do |fixture_name, (content, ref, dry_run)|
      it "#{base_output_path}#{fixture_name}.mutation.graphql.json" do
        mutation = get_graphql_query_as_string('ci/pipeline_editor/graphql/mutations/ci_lint.mutation.graphql')

        post_graphql(mutation, current_user: user, variables: {
          projectPath: project.full_path,
          content: content,
          ref: ref,
          dryRun: dry_run
        })

        expect_graphql_errors_to_be_empty
      end
    end
  end
end
