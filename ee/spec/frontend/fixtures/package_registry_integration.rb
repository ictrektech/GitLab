# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Package registry Integration (GraphQL fixtures)', type: :request,
  feature_category: :package_registry do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  pipeline_shas = %w[c83d6e391c22777fca1ed3012fce84f633d7fed0 d83d6e391c22777fca1ed3012fce84f633d7fed0]

  let_it_be(:user) { create(:user, name: 'Package Publisher', username: 'package-publisher') }
  let_it_be(:owner) { create(:user, :with_namespace, username: 'packages-owner') }

  let_it_be(:project) do
    create(:project, namespace: owner.namespace, name: 'registry-project', path: 'registry-project',
      maintainers: user)
  end

  let_it_be(:group) { create(:group, path: 'packages-group', maintainers: user) }
  let_it_be(:project_zzz) { create(:project, group: group, name: 'project-zzz', path: 'project-zzz') }
  let_it_be(:project_aaa) { create(:project, group: group, name: 'project-aaa', path: 'project-aaa') }

  let_it_be(:project_npm) do
    create(:npm_package, project: project, name: 'zzz', created_at: 1.day.ago, version: '1.0.0')
  end

  let_it_be(:project_maven) do
    create(:maven_package, project: project, name: 'aaa', created_at: 2.days.ago, version: '2.0.0')
  end

  let_it_be(:group_npm) do
    create(:npm_package, project: project_zzz, name: 'zzz', created_at: 1.day.ago, version: '1.0.0')
  end

  let_it_be(:group_maven) do
    create(:maven_package, project: project_aaa, name: 'aaa', created_at: 2.days.ago, version: '2.0.0')
  end

  before_all do
    [project_npm, group_npm].product(pipeline_shas).each do |package, sha|
      pipeline = create(:ci_pipeline, project: package.project, user: user, sha: sha)
      create(:package_build_info, package: package, pipeline: pipeline)
    end
  end

  base_output_path = 'graphql/packages_and_registries/package_registry/integration/'

  sorts = %w[CREATED_DESC CREATED_ASC NAME_DESC NAME_ASC VERSION_DESC VERSION_ASC TYPE_DESC TYPE_ASC]

  page_size = 20
  pipelines_page_size = 10
  files_page_size = 20

  def page_variables(page)
    { fullPath: public_send(page).full_path, isGroupPage: page == :group }
  end

  def post_fixture_query(query_file, variables)
    query = get_graphql_query_as_string("packages_and_registries/package_registry/graphql/#{query_file}")

    post_graphql(query, current_user: user, variables: variables)
  end

  def package_gid(package)
    package.to_global_id.to_s
  end

  describe GraphQL::Query, 'list' do
    {
      project: ['', :sort, sorts],
      group: ['_group', :groupSort, sorts + %w[PROJECT_PATH_DESC PROJECT_PATH_ASC]]
    }.each do |page, (suffix, sort_variable, page_sorts)|
      page_sorts.each do |sort|
        it "#{base_output_path}get_packages#{suffix}_#{sort.downcase}.query.graphql.json" do
          post_fixture_query('queries/get_packages.query.graphql',
            page_variables(page).merge(sort_variable => sort, first: page_size))

          expect_graphql_errors_to_be_empty
          expect(graphql_data_at(page, :packages, :nodes).pluck('name')).to match_array(%w[zzz aaa])
        end
      end

      it "#{base_output_path}get_packages#{suffix}_type_npm.query.graphql.json" do
        post_fixture_query('queries/get_packages.query.graphql',
          page_variables(page).merge(sort_variable => 'CREATED_DESC', packageType: 'NPM', first: page_size))

        nodes = graphql_data_at(page, :packages, :nodes)

        expect_graphql_errors_to_be_empty
        expect(nodes.pluck('name')).to eq(%w[zzz])
        expect(nodes.first.dig('pipelines', 'nodes', 0, 'sha')).to eq(pipeline_shas.last)
      end

      it "#{base_output_path}get_packages_count#{suffix}.query.graphql.json" do
        post_fixture_query('queries/get_packages_count.query.graphql', page_variables(page))

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_packages_count#{suffix}_type_npm.query.graphql.json" do
        post_fixture_query('queries/get_packages_count.query.graphql', page_variables(page).merge(packageType: 'NPM'))

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_package_errors_count#{suffix}.query.graphql.json" do
        post_fixture_query('queries/get_package_errors_count.query.graphql', page_variables(page))

        expect_graphql_errors_to_be_empty
      end

      it "#{base_output_path}get_group_package_settings#{suffix}.query.graphql.json" do
        post_fixture_query('queries/get_group_package_settings.query.graphql', page_variables(page))

        expect_graphql_errors_to_be_empty
      end
    end
  end

  describe GraphQL::Query, 'details' do
    it "#{base_output_path}get_group_package_settings_group_project_zzz.query.graphql.json" do
      post_fixture_query('queries/get_group_package_settings.query.graphql', { fullPath: project_zzz.full_path })

      expect_graphql_errors_to_be_empty
    end

    shared_examples 'package fixtures' do |package_names, versions_count:, queries: {}|
      package_names.each do |package_name|
        it "#{base_output_path}get_package_details_#{package_name}.query.graphql.json" do
          post_fixture_query('queries/get_package_details.query.graphql',
            { id: package_gid(public_send(package_name)) })

          expect_graphql_errors_to_be_empty
          expect(graphql_data.dig('package', 'versions', 'count')).to eq(versions_count)
        end

        queries.each do |query, first|
          it "#{base_output_path}#{query}_#{package_name}.query.graphql.json" do
            post_fixture_query("queries/#{query}.query.graphql",
              { id: package_gid(public_send(package_name)), first: first })

            expect_graphql_errors_to_be_empty
          end
        end
      end
    end

    package_queries = { 'get_package_pipelines' => pipelines_page_size, 'get_package_files' => files_page_size }

    include_examples 'package fixtures', %w[project_maven group_maven], versions_count: 0
    include_examples 'package fixtures', %w[project_npm group_npm], versions_count: 0, queries: package_queries

    context 'with other versions' do
      before_all do
        create(:npm_package, project: project, name: 'zzz', version: '1.1.0')
        create(:npm_package, project: project_zzz, name: 'zzz', version: '1.1.0')
      end

      let_it_be(:project_npm_newest) { create(:npm_package, project: project, name: 'zzz', version: '1.2.0') }
      let_it_be(:group_npm_newest) { create(:npm_package, project: project_zzz, name: 'zzz', version: '1.2.0') }

      include_examples 'package fixtures', %w[project_npm_newest group_npm_newest], versions_count: 2,
        queries: { 'get_package_versions' => page_size }.merge(package_queries)
    end
  end

  describe GraphQL::Query, 'mutations' do
    it "#{base_output_path}destroy_packages.mutation.graphql.json" do
      post_fixture_query('mutations/destroy_packages.mutation.graphql', { ids: [package_gid(project_maven)] })

      expect_graphql_errors_to_be_empty
      expect(graphql_data.dig('destroyPackages', 'errors')).to be_empty
    end
  end
end
