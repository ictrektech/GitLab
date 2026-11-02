# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Container registry Integration (GraphQL fixtures)', type: :request,
  feature_category: :container_registry do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  include_context 'container registry tags'

  let(:registry_api_url) { 'http://registry.gitlab' }

  let_it_be(:user) { create(:user, name: 'Registry Developer', username: 'registry-developer') }
  let_it_be(:namespace) { create(:group, name: 'registry-fixtures', path: 'registry-fixtures') }

  let_it_be(:project) do
    create(:project, namespace: namespace, name: 'registry-project', path: 'registry-project', developers: user)
  end

  let_it_be(:project_nameless) do
    create(:project, namespace: namespace, name: 'registry-project-nameless', path: 'registry-project-nameless',
      developers: user)
  end

  let_it_be(:project_many) do
    create(:project, namespace: namespace, name: 'registry-project-many', path: 'registry-project-many',
      developers: user)
  end

  let_it_be(:group) { create(:group, name: 'registry-group', path: 'registry-group', owners: user) }

  let_it_be(:group_same_name) do
    create(:group, name: 'registry-group-same-name', path: 'registry-group-same-name', owners: user)
  end

  let_it_be(:group_project) { create(:project, group: group, name: 'group-project', path: 'group-project') }

  let_it_be(:group_same_name_project) do
    create(:project, group: group_same_name, name: 'same-name-project', path: 'same-name-project')
  end

  let_it_be(:repository_project) { create(:container_repository, project: project, name: 'my/image') }
  let_it_be(:repository_nameless) { create(:container_repository, project: project_nameless, name: '') }
  let_it_be(:repository_group) { create(:container_repository, project: group_project, name: 'my/image') }

  let_it_be(:repository_same_name) do
    create(:container_repository, project: group_same_name_project, name: group_same_name.name)
  end

  let_it_be(:repository_many) do
    create(:container_repository, project: project_many, name: 'my/image', created_at: 1.day.ago,
      updated_at: 1.day.ago)
  end

  before_all do
    # rubocop:disable FactoryBot/ExcessiveCreateList -- 21 repositories are needed so the paginator can serve a second list page at 20 per page
    create_list(:container_repository, 20, project: project_many)
    # rubocop:enable FactoryBot/ExcessiveCreateList
  end

  base_output_path = 'graphql/packages_and_registries/container_registry/integration/'
  graphql_path = 'packages_and_registries/container_registry/explorer/graphql/'

  page_size = 20
  all_nodes = 100
  default_tags_sort = 'PUBLISHED_AT_DESC'
  tags_many = ('1'..'25').to_a

  before do
    stub_container_registry_config(enabled: true, api_url: registry_api_url, host_port: 'registry.gitlab')
    stub_container_registry_info
    stub_container_registry_tags(repository: :any, tags: [])
    stub_request(:get, "#{registry_api_url}/gitlab/v1/").to_return(status: 404)
  end

  def post_fixture_query(query, variables)
    post_graphql(query, current_user: user, variables: variables)
  end

  def explorer_query(file)
    get_graphql_query_as_string("packages_and_registries/container_registry/explorer/graphql/#{file}")
  end

  def repositories_query
    get_graphql_query_as_string('app/graphql/queries/container_registry/get_container_repositories.query.graphql',
      with_base_path: false)
  end

  def tags_query
    explorer_query('queries/get_container_repository_tags.query.graphql')
  end

  def gid(record)
    record.to_global_id.to_s
  end

  def stub_tags(repository, tags, with_manifest: true)
    stub_container_registry_tags(repository: repository.path, tags: tags, with_manifest: with_manifest)
  end

  def list_variables(container, group_page:, first:)
    { fullPath: container.full_path, isGroupPage: group_page, first: first, sort: 'UPDATED_DESC' }
  end

  describe GraphQL::Query, 'list' do
    {
      'project_repositories' => [:project, false, page_size, ['my/image']],
      'project_repositories_nameless' => [:project_nameless, false, page_size, ['']],
      'group_repositories' => [:group, true, page_size, ['my/image']],
      'group_repositories_same_name' => [:group_same_name, true, page_size, ['registry-group-same-name']]
    }.each do |name, (container, group_page, first, names)|
      resource = group_page ? :group : :project
      details_name = name.sub('_repositories', '_repositories_details')

      it "#{base_output_path}#{name}.query.graphql.json" do
        post_fixture_query(repositories_query,
          list_variables(public_send(container), group_page: group_page, first: first))

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(resource, :container_repositories_count)).to eq(names.size)
        expect(graphql_data_at(resource, :container_repositories, :nodes).pluck('name')).to eq(names)
      end

      it "#{base_output_path}#{details_name}.query.graphql.json" do
        post_fixture_query(explorer_query('queries/get_container_repositories_details.query.graphql'),
          list_variables(public_send(container), group_page: group_page, first: first))

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(resource, :container_repositories, :nodes).size).to eq(names.size)
      end
    end

    it "#{base_output_path}project_repositories_many.query.graphql.json" do
      post_fixture_query(repositories_query, list_variables(project_many, group_page: false, first: all_nodes))

      nodes = graphql_data_at(:project, :container_repositories, :nodes)

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :container_repositories_count)).to eq(21)
      expect(nodes.size).to eq(21)
      expect(nodes.last['name']).to eq('my/image')
    end

    it "#{base_output_path}project_repositories_details_many.query.graphql.json" do
      post_fixture_query(explorer_query('queries/get_container_repositories_details.query.graphql'),
        list_variables(project_many, group_page: false, first: all_nodes))

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :container_repositories, :nodes).size).to eq(21)
    end
  end

  describe GraphQL::Query, 'details' do
    {
      'project' => :repository_project,
      'nameless' => :repository_nameless,
      'many' => :repository_many,
      'group' => :repository_group,
      'same_name' => :repository_same_name
    }.each do |suffix, repository|
      it "#{base_output_path}repository_details_#{suffix}.query.graphql.json" do
        post_fixture_query(explorer_query('queries/get_container_repository_details.query.graphql'),
          { id: gid(public_send(repository)) })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:container_repository, :id)).to eq(gid(public_send(repository)))
      end

      it "#{base_output_path}repository_metadata_#{suffix}.query.graphql.json" do
        stub_tags(public_send(repository), %w[latest])

        post_fixture_query(explorer_query('queries/get_container_repository_metadata.query.graphql'),
          { id: gid(public_send(repository)), metadataDatabaseEnabled: true })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:container_repository, :tags_count)).to eq(1)
      end

      it "#{base_output_path}repository_tags_#{suffix}.query.graphql.json" do
        stub_tags(public_send(repository), %w[latest])

        post_fixture_query(tags_query, { id: gid(public_send(repository)), first: page_size, sort: default_tags_sort })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:container_repository, :tags, :nodes).pluck('name')).to eq(%w[latest])
      end
    end

    it "#{base_output_path}repository_metadata_project_many.query.graphql.json" do
      stub_tags(repository_project, tags_many)

      post_fixture_query(explorer_query('queries/get_container_repository_metadata.query.graphql'),
        { id: gid(repository_project), metadataDatabaseEnabled: true })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:container_repository, :tags_count)).to eq(tags_many.size)
    end

    it "#{base_output_path}repository_tags_project_many.query.graphql.json" do
      stub_tags(repository_project, tags_many)

      post_fixture_query(tags_query, { id: gid(repository_project), first: page_size, sort: default_tags_sort })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:container_repository, :tags_count)).to eq(tags_many.size)
      expect(graphql_data_at(:container_repository, :tags, :nodes).size).to eq(page_size)
      expect(graphql_data_at(:container_repository, :tags, :page_info, :has_next_page)).to be(true)
    end

    {
      'repository_tags_project_many_name_desc' => [tags_many, 'NAME_DESC', tags_many.sort.reverse],
      'repository_tags_project_many_name_asc' => [tags_many, 'NAME_ASC', tags_many.sort]
    }.each do |name, (tags, sort, sorted_names)|
      it "#{base_output_path}#{name}.query.graphql.json" do
        stub_tags(repository_project, tags)

        post_fixture_query(tags_query, { id: gid(repository_project), first: page_size, sort: sort })

        expect_graphql_errors_to_be_empty
        expect(graphql_data_at(:container_repository, :tags_count)).to eq(tags.size)
        expect(graphql_data_at(:container_repository, :tags, :nodes).pluck('name'))
          .to eq(sorted_names.first(page_size))
        expect(graphql_data_at(:container_repository, :tags, :page_info, :has_next_page)).to be(true)
      end
    end

    it "#{base_output_path}repository_tags_project_many_page_2.query.graphql.json" do
      variables = { id: gid(repository_project), first: page_size, sort: 'NAME_ASC' }
      stub_tags(repository_project, tags_many)

      post_fixture_query(tags_query, variables)
      end_cursor = graphql_data_at(:container_repository, :tags, :page_info, :end_cursor)

      post_fixture_query(tags_query, variables.merge(after: end_cursor))

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:container_repository, :tags, :nodes).pluck('name'))
        .to eq(tags_many.sort - tags_many.sort.first(page_size))
      expect(graphql_data_at(:container_repository, :tags, :page_info, :has_previous_page)).to be(true)
    end

    it "#{base_output_path}repository_tags_project_missing_digest.query.graphql.json" do
      stub_tags(repository_project, %w[latest stable])
      stub_next_container_registry_tags_call(:digest, nil)

      post_fixture_query(tags_query, { id: gid(repository_project), first: page_size, sort: default_tags_sort })

      nodes = graphql_data_at(:container_repository, :tags, :nodes)

      expect_graphql_errors_to_be_empty
      expect(nodes.pluck('name')).to match_array(%w[latest stable])
      expect(nodes.pluck('digest')).to include(nil)
    end
  end

  describe GraphQL::Query, 'scanning' do
    it "#{base_output_path}get_project_container_scanning.query.graphql.json" do
      query = get_graphql_query_as_string("#{graphql_path}queries/get_project_container_scanning.query.graphql",
        ee: true)

      post_fixture_query(query, {
        fullPath: project.full_path,
        reportType: %w[CONTAINER_SCANNING_FOR_REGISTRY],
        state: %w[DETECTED CONFIRMED],
        capped: true
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :id)).to eq(gid(project))
    end
  end

  describe Projects::Security::ConfigurationController, '(JavaScript fixtures)' do
    it "#{base_output_path}rest_security_configuration.json" do
      sign_in(user)

      get project_security_configuration_path(project, format: :json)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.parsed_body).to have_key('container_scanning_for_registry_enabled')
    end
  end

  describe GraphQL::Query, 'mutations' do
    def stub_registry_tag_delete(repository, tag)
      stub_request(:options, "#{registry_api_url}/v2/name/manifests/tag")
        .to_return(status: 200, headers: { 'Allow' => 'DELETE' })
      stub_request(:delete, "#{registry_api_url}/v2/#{repository.path}/manifests/#{tag}").to_return(status: 202)
    end

    it "#{base_output_path}destroy_container_repository_tags.mutation.graphql.json" do
      stub_tags(repository_project, tags_many)
      stub_registry_tag_delete(repository_project, '1')

      post_fixture_query(explorer_query('mutations/delete_container_repository_tags.mutation.graphql'),
        { id: gid(repository_project), tagNames: %w[1] })

      expect_graphql_errors_to_be_empty
      expect(graphql_mutation_response(:destroy_container_repository_tags)['errors']).to eq([])
    end

    it "#{base_output_path}destroy_container_repository.mutation.graphql.json" do
      post_fixture_query(explorer_query('mutations/delete_container_repository.mutation.graphql'),
        { id: gid(repository_project) })

      expect_graphql_errors_to_be_empty
      expect(graphql_mutation_response(:destroy_container_repository)['errors']).to eq([])
      expect(graphql_mutation_response(:destroy_container_repository).dig('containerRepository', 'status'))
        .to eq('DELETE_SCHEDULED')
    end
  end
end
