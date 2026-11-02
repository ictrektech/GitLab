# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::ApplicationsController, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, owners: user) }
  let_it_be(:application) { create(:oauth_application, owner_id: group.id, owner_type: 'Namespace') }
  let(:show_path) { group_settings_application_path(group, application) }
  let(:create_path) { group_settings_applications_path(group) }

  before do
    sign_in(user)
  end

  include_examples 'applications controller - GET #show'

  include_examples 'applications controller - POST #create'

  context 'on GET #index' do
    def perform_scopes_action
      get group_settings_applications_path(group)
    end

    include_examples 'applications controller - scopes include mcp'
  end

  context 'on GET #edit' do
    def perform_scopes_action
      get edit_group_settings_application_path(group, application)
    end

    include_examples 'applications controller - scopes include mcp'
  end

  describe 'granular scopes' do
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:other_group) { create(:group) }

    let(:granular_scope_params) do
      {
        granular_scopes: {
          '0' => { access: 'USER', permissions: ['execute_mcp_tool'] },
          '1' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                   resource_ids: [subgroup.to_global_id.to_s] }
        }
      }
    end

    def declared(application)
      application.reload.granular_scopes.map { |scope| [scope.access, scope.namespace_id] }
    end

    def created_application
      Authn::OauthApplication.find_by!(name: create_params[:name])
    end

    def picker_element
      Nokogiri::HTML(response.body).at_css('#js-oauth-application-granular-scopes')
    end

    describe 'GET #index' do
      it 'mounts the picker with the levels a group application may declare', :aggregate_failures do
        get group_settings_applications_path(group)

        expect(picker_element['data-allowed-access-levels']).to eq('["USER","SELECTED_MEMBERSHIPS"]')
        expect(picker_element['data-group-full-path']).to eq(group.full_path)
        expect(picker_element['data-group-name']).to eq(group.name)
        expect(picker_element['data-initial-scopes']).to eq('[]')
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(granular_oauth_tokens: false)
        end

        it 'does not mount the picker' do
          get group_settings_applications_path(group)

          expect(picker_element).to be_nil
        end
      end
    end

    describe 'GET #show' do
      let_it_be(:project) { create(:project, group: subgroup) }
      let_it_be(:one_scope_application) do
        create(:oauth_application, :granular, owner_id: group.id, owner_type: 'Namespace',
          boundary: Authz::Boundary.for(subgroup), permissions: ['read_member_role'])
      end

      let_it_be(:multi_scope_application) do
        create(:oauth_application, :granular, owner_id: group.id, owner_type: 'Namespace',
          boundary: Authz::Boundary.for(project), permissions: ['read_member_role']).tap do |app|
          create(:oauth_application_granular_scope, application: app,
            granular_scope: create(:granular_scope, boundary: Authz::Boundary.for(subgroup),
              permissions: ['read_member_role']))
          create(:oauth_application_granular_scope, application: app,
            granular_scope: create(:granular_scope, boundary: Authz::Boundary.for(:user),
              permissions: ['execute_mcp_tool']))
        end
      end

      it 'lists the declared fine-grained permissions', :aggregate_failures do
        get group_settings_application_path(group, multi_scope_application)

        expect(response.body).to include('Fine-grained permissions')
        expect(response.body).to include('User permissions')
        expect(response.body).to include('execute_mcp_tool')
        expect(response.body).to include('Grants the ability to execute tools through the MCP server')
      end

      it 'has no fine-grained permissions row for a legacy application' do
        get show_path

        expect(response.body).not_to include('Fine-grained permissions')
      end

      it 'lists every declared scope without a query per scope', :aggregate_failures do
        # Warm up the caches a first request fills regardless of the application
        get group_settings_application_path(group, one_scope_application)

        control = ActiveRecord::QueryRecorder.new do
          get group_settings_application_path(group, one_scope_application)
        end

        expect { get group_settings_application_path(group, multi_scope_application) }
          .to issue_same_number_of_queries_as(control).ignoring_cached_queries

        expect(response.body).to include(project.full_path, subgroup.full_path, 'execute_mcp_tool')
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(granular_oauth_tokens: false)
        end

        it 'has no fine-grained permissions row and does not load the declared scopes', :aggregate_failures do
          recorder = ActiveRecord::QueryRecorder.new do
            get group_settings_application_path(group, multi_scope_application)
          end

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).not_to include('Fine-grained permissions')
          expect(recorder.log).not_to include(a_string_matching(/granular_scopes/))
        end
      end
    end

    describe 'POST #create' do
      let(:create_params) { attributes_for(:application, confidential: false, scopes: ['api']) }

      subject(:create_application) do
        post create_path, params: { authn_oauth_application: create_params.merge(granular_scope_params) }
      end

      it 'declares the set on the new application next to the posted scopes', :aggregate_failures do
        create_application

        expect(response).to have_gitlab_http_status(:ok)
        expect(declared(created_application)).to contain_exactly(['user', nil], ['selected_memberships', subgroup.id])
        expect(created_application.scopes.to_a).to contain_exactly('api', 'granular')
      end

      context 'without scopes' do
        let(:create_params) { attributes_for(:application, confidential: false) }

        it 'creates an application with only the granular scope', :aggregate_failures do
          create_application

          expect(response).to have_gitlab_http_status(:ok)
          expect(declared(created_application)).to contain_exactly(['user', nil], ['selected_memberships', subgroup.id])
          expect(created_application.scopes.to_a).to eq(['granular'])
        end
      end

      context 'when the scopes are posted as an array' do
        let(:granular_scope_params) do
          { granular_scopes: [{ access: 'USER', permissions: ['execute_mcp_tool'] }] }
        end

        it 'declares the set on the new application' do
          create_application

          expect(declared(created_application)).to contain_exactly(['user', nil])
        end
      end

      context 'when rendering the created application' do
        let_it_be(:more_subgroups) { create_list(:group, 2, parent: group) }

        def route_queries_creating(name, groups)
          params = create_params.merge(
            name: name,
            granular_scopes: { '0' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                                        resource_ids: groups.map { |g| g.to_global_id.to_s } } }
          )

          ActiveRecord::QueryRecorder.new { post create_path, params: { authn_oauth_application: params } }
            .log.count { |query| query.include?('FROM "routes"') }
        end

        it 'loads the namespace paths without a query per scope', :aggregate_failures do
          control = route_queries_creating('one scope', [subgroup])

          expect(route_queries_creating('three scopes', [subgroup, *more_subgroups])).to eq(control)
          expect(response.body).to include(subgroup.full_path, *more_subgroups.map(&:full_path))
        end
      end

      context 'when the set has only group and project scopes' do
        let(:granular_scope_params) do
          { granular_scopes: { '0' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                                        resource_ids: [subgroup.to_global_id.to_s] } } }
        end

        it 'declares the set on the new application', :aggregate_failures do
          create_application

          expect(response).to have_gitlab_http_status(:ok)
          expect(declared(created_application)).to contain_exactly(['selected_memberships', subgroup.id])
        end
      end

      context 'when a resource is neither a group nor a project' do
        let(:granular_scope_params) do
          { granular_scopes: { '0' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                                        resource_ids: [user.to_global_id.to_s] } } }
        end

        it 'ignores it and refuses the empty selection', :aggregate_failures do
          expect { create_application }.not_to change { Authn::OauthApplication.count }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('Selected memberships access requires at least one group or project.')
        end
      end

      context 'when a resource names a class that does not exist' do
        let(:granular_scope_params) do
          { granular_scopes: { '0' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                                        resource_ids: ['gid://gitlab/Nope/1'] } } }
        end

        it 'ignores it and refuses the empty selection', :aggregate_failures do
          expect { create_application }.not_to change { Authn::OauthApplication.count }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('Selected memberships access requires at least one group or project.')
        end
      end

      context 'when the declaration is refused' do
        let(:granular_scope_params) do
          { granular_scopes: { '0' => { access: 'SELECTED_MEMBERSHIPS', permissions: ['read_member_role'],
                                        resource_ids: [other_group.to_global_id.to_s] } } }
        end

        it 'creates nothing and renders the form with the reason', :aggregate_failures do
          expect { create_application }.not_to change { Authn::OauthApplication.count }

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).to include('A selected group or project cannot be a boundary for this application.')
        end

        it 'hands the posted scopes back to the picker without the outside namespace' do
          create_application

          expect(Gitlab::Json::SafeParser.parse(picker_element['data-initial-scopes'])).to eq([
            { 'access' => 'SELECTED_MEMBERSHIPS', 'permissions' => ['read_member_role'], 'namespaces' => [] }
          ])
        end
      end

      context 'when the application is invalid' do
        let(:create_params) { attributes_for(:application, name: '', confidential: false, scopes: ['api']) }

        it 'hands the posted scopes back to the picker with the namespaces resolved' do
          create_application

          expect(Gitlab::Json::SafeParser.parse(picker_element['data-initial-scopes'])).to eq([
            { 'access' => 'USER', 'permissions' => ['execute_mcp_tool'], 'namespaces' => [] },
            {
              'access' => 'SELECTED_MEMBERSHIPS',
              'permissions' => ['read_member_role'],
              'namespaces' => [{
                'id' => subgroup.to_global_id.to_s, '__typename' => 'Group',
                'name' => subgroup.name, 'fullPath' => subgroup.full_path
              }]
            }
          ])
        end
      end

      context 'without granular scopes' do
        let(:granular_scope_params) { {} }

        it 'creates a legacy application', :aggregate_failures do
          create_application

          expect(response).to have_gitlab_http_status(:ok)
          expect(declared(created_application)).to be_empty
          expect(created_application.scopes.to_a).to eq(['api'])
        end

        context 'without scopes either' do
          let(:create_params) { attributes_for(:application, confidential: false) }

          it 'creates nothing and renders the form with the reason', :aggregate_failures do
            expect { create_application }.not_to change { Authn::OauthApplication.count }

            expect(response.body).to include('Scopes can&#39;t be blank')
          end
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(granular_oauth_tokens: false)
        end

        it 'ignores the posted scopes', :aggregate_failures do
          create_application

          expect(response).to have_gitlab_http_status(:ok)
          expect(declared(created_application)).to be_empty
        end
      end

      context 'when the user is not an owner' do
        let_it_be(:maintainer) { create(:user, maintainer_of: group) }

        before do
          sign_in(maintainer)
        end

        it 'returns 404 and creates nothing', :aggregate_failures do
          expect { create_application }.not_to change { Authn::OauthApplication.count }

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
