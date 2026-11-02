# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Repository Path Locks Integration (GraphQL fixtures)', type: :request,
  feature_category: :source_code_management do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  # The lock card and "Locked by" assertions read this name, so it is pinned
  # rather than left to the User factory sequence.
  # :with_namespace because blob controls paths (ide_edit_path, fork checks)
  # dereference the user's personal namespace.
  let_it_be(:user) { create(:user, :with_namespace, name: 'Lock Owner', username: 'lock-owner') }
  let_it_be(:developer) { create(:user, name: 'Dev Viewer', username: 'dev-viewer') }
  let_it_be(:reporter) { create(:user, :with_namespace, name: 'Report Viewer', username: 'report-viewer') }
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:archived_project) { create(:project, :repository, :archived) }

  before_all do
    project.add_maintainer(user)
    project.add_developer(developer)
    project.add_reporter(reporter)
    archived_project.add_maintainer(user)
  end

  before do
    stub_licensed_features(file_locks: true)
  end

  base_output_path = 'graphql/repository/integration/'
  project_info_query = 'repository/queries/project_info.query.graphql'

  def project_info_lock_nodes
    graphql_data.dig('project', 'pathLocks', 'nodes')
  end

  describe GraphQL::Query do
    it "#{base_output_path}get_project_info.query.graphql.json" do
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(project_info_lock_nodes).to be_empty
      expect(graphql_data.dig('project', 'userPermissions', 'createPathLock')).to be(true)
    end

    it "#{base_output_path}get_project_info_file_locked_by_other.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'VERSION')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: developer, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      # Guards the fixture's purpose: a developer cannot unlock another user's lock.
      expect(project_info_lock_nodes.first.dig('userPermissions', 'destroyPathLock')).to be(false)
    end

    it "#{base_output_path}get_project_info_directory_locked.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'encoding')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(project_info_lock_nodes.first['path']).to eq('encoding')
    end

    it "#{base_output_path}get_project_info_locked.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'VERSION')
      create(:path_lock, project: project, user: user, path: 'encoding')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(project_info_lock_nodes.map { |n| n['path'] }).to contain_exactly('VERSION', 'encoding')
    end

    it "#{base_output_path}get_project_info_directory_locked_as_reporter.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'encoding')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: reporter, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      # Guards the fixture's purpose: the lock stays visible to a user who can
      # neither create nor destroy locks (the regression fixed in !250523).
      expect(graphql_data.dig('project', 'userPermissions', 'createPathLock')).to be(false)
      expect(project_info_lock_nodes.first.dig('userPermissions', 'destroyPathLock')).to be(false)
    end

    it "#{base_output_path}get_project_info_files_directory_locked.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'files')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(project_info_lock_nodes.first['path']).to eq('files')
    end

    it "#{base_output_path}get_project_info_nested_directory_locked.query.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'files/ruby')
      query = get_graphql_query_as_string(project_info_query, ee: true)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
      expect(project_info_lock_nodes.first['path']).to eq('files/ruby')
    end

    it "#{base_output_path}get_blob_controls.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/blob_controls.query.graphql')

      post_graphql(query, current_user: user,
        variables: { projectPath: project.full_path, filePath: 'VERSION', ref: 'master' })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('project', 'repository', 'blobs', 'nodes', 0, 'path')).to eq('VERSION')
    end

    it "#{base_output_path}get_blob_controls_nested.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/blob_controls.query.graphql')

      post_graphql(query, current_user: user,
        variables: { projectPath: project.full_path, filePath: 'encoding/test.txt', ref: 'master' })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('project', 'repository', 'blobs', 'nodes', 0, 'path')).to eq('encoding/test.txt')
    end

    it "#{base_output_path}get_blob_controls_non_writable.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/blob_controls.query.graphql')

      post_graphql(query, current_user: reporter,
        variables: { projectPath: project.full_path, filePath: 'VERSION', ref: 'master' })

      expect_graphql_errors_to_be_empty
      # Guards the fixture's purpose: a reporter cannot edit directly but can
      # fork, which is the state that triggers the fork suggestion modal.
      blob = graphql_data.dig('project', 'repository', 'blobs', 'nodes', 0)
      expect(blob['canModifyBlob']).to be(false)
      expect(blob['canModifyBlobWithWebIde']).to be(false)
      expect(blob['forkAndViewPath']).to be_present
      expect(graphql_data.dig('project', 'userPermissions', 'forkProject')).to be(true)
      expect(graphql_data.dig('project', 'userPermissions', 'createMergeRequestIn')).to be(true)
    end

    it "#{base_output_path}get_blob_controls_archived.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/blob_controls.query.graphql')

      post_graphql(query, current_user: user,
        variables: { projectPath: archived_project.full_path, filePath: 'VERSION', ref: 'master' })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('project', 'repository', 'blobs', 'nodes', 0, 'archived')).to be(true)
    end

    it "#{base_output_path}get_blob_controls_binary.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/blob_controls.query.graphql')

      post_graphql(query, current_user: user,
        variables: { projectPath: project.full_path, filePath: 'files/images/logo-black.png', ref: 'master' })

      expect_graphql_errors_to_be_empty
      # Guards the fixture's purpose: a non-text viewer hides the single file editor.
      expect(graphql_data.dig('project', 'repository', 'blobs', 'nodes', 0, 'simpleViewer',
        'fileType')).not_to eq('text')
    end

    it "#{base_output_path}get_user_gitpod_info.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/user_gitpod_info.query.graphql')

      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_application_info.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/application_info.query.graphql')

      post_graphql(query, current_user: user)

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_permissions.query.graphql.json" do
      query = get_graphql_query_as_string('app/graphql/queries/repository/permissions.query.graphql',
        with_base_path: false)

      post_graphql(query, current_user: user, variables: { projectPath: project.full_path })

      expect_graphql_errors_to_be_empty
    end

    it "#{base_output_path}get_permalink_path.query.graphql.json" do
      query = get_graphql_query_as_string('repository/queries/permalink_path.query.graphql')

      post_graphql(query, current_user: user,
        variables: { fullPath: project.full_path, path: 'encoding', ref: 'master' })

      expect_graphql_errors_to_be_empty
    end
  end

  describe GraphQL::Query, 'mutations' do
    let(:mutation) { get_graphql_query_as_string('repository/mutations/lock_path.mutation.graphql') }

    it "#{base_output_path}toggle_lock.mutation.graphql.json" do
      post_graphql(mutation, current_user: user,
        variables: { projectPath: project.full_path, filePath: 'VERSION', lock: true })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('projectSetLocked', 'errors')).to be_empty
    end

    it "#{base_output_path}toggle_lock_unlock.mutation.graphql.json" do
      create(:path_lock, project: project, user: user, path: 'VERSION')

      post_graphql(mutation, current_user: user,
        variables: { projectPath: project.full_path, filePath: 'VERSION', lock: false })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('projectSetLocked', 'project', 'pathLocks', 'nodes')).to be_empty
    end
  end
end
