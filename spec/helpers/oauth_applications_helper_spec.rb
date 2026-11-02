# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OauthApplicationsHelper, feature_category: :system_access do
  describe '#granular_scopes_for_display' do
    let(:zeta_scope) do
      build_stubbed(:granular_scope, access: :selected_memberships, namespace: build_stubbed(:group, path: 'zeta'))
    end

    let(:alpha_scope) do
      build_stubbed(:granular_scope, access: :selected_memberships, namespace: build_stubbed(:group, path: 'alpha'))
    end

    let(:user_scope) { build_stubbed(:granular_scope, access: :user, namespace: nil) }

    it 'orders scopes by access level and then by namespace path' do
      expect(helper.granular_scopes_for_display([zeta_scope, user_scope, alpha_scope]))
        .to eq([alpha_scope, zeta_scope, user_scope])
    end
  end

  describe '#granular_scope_access_text' do
    using RSpec::Parameterized::TableSyntax

    where(:access, :text) do
      :selected_memberships | 'Only specific groups or projects I have access to'
      :user                 | 'User permissions'
    end

    with_them do
      it 'describes the access level' do
        scope = build_stubbed(:granular_scope, access: access, namespace: nil)

        expect(helper.granular_scope_access_text(scope)).to eq(text)
      end
    end

    context 'with an access level that has no label' do
      where(:access) { %i[personal_projects all_memberships instance] }

      with_them do
        it 'raises' do
          scope = build_stubbed(:granular_scope, access: access, namespace: nil)

          expect { helper.granular_scope_access_text(scope) }
            .to raise_error(ArgumentError, "Unsupported granular scope access: #{access}")
        end
      end
    end
  end

  describe '#granular_scope_namespace_label' do
    let(:group) { build_stubbed(:group) }

    it 'labels a group' do
      expect(helper.granular_scope_namespace_label(group)).to eq('Group')
    end

    it 'labels a project namespace' do
      project_namespace = build_stubbed(:project_namespace, project: nil, parent: group, name: 'Widgets',
        path: 'widgets', visibility_level: Gitlab::VisibilityLevel::PRIVATE)

      expect(helper.granular_scope_namespace_label(project_namespace)).to eq('Project')
    end
  end

  describe '#granular_permission_description' do
    it 'returns the description of a known permission' do
      expect(helper.granular_permission_description('execute_mcp_tool'))
        .to eq('Grants the ability to execute tools through the MCP server')
    end

    it 'returns nil for an unknown permission' do
      expect(helper.granular_permission_description('unknown_permission')).to be_nil
    end
  end

  describe '#oauth_application_granular_scopes_picker_data' do
    let(:user) { build_stubbed(:user) }
    let(:group) { build_stubbed(:group, name: 'Acme', path: 'acme') }

    before do
      allow(helper).to receive(:current_user).and_return(user)
    end

    it 'returns the picker data for a group owner' do
      expect(helper.oauth_application_granular_scopes_picker_data(group, nil)).to eq(
        allowed_access_levels: '["USER","SELECTED_MEMBERSHIPS"]',
        group_full_path: 'acme',
        group_name: 'Acme',
        initial_scopes: '[]'
      )
    end

    it 'returns nil for a user owner' do
      expect(helper.oauth_application_granular_scopes_picker_data(user, nil)).to be_nil
    end

    it 'returns nil without an owner' do
      expect(helper.oauth_application_granular_scopes_picker_data(nil, nil)).to be_nil
    end

    context 'with posted inputs' do
      # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the hierarchy boundary is a database query
      let_it_be(:owner) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: owner, name: 'Widgets') }
      let_it_be(:project) { create(:project, group: subgroup, name: 'Site') }
      let_it_be(:outside_group) { create(:group) }
      let_it_be(:outside_project) { create(:project) }
      let_it_be(:more_subgroups) { create_list(:group, 2, parent: owner) }
      let_it_be(:more_projects) { create_list(:project, 2, group: subgroup) }
      # rubocop:enable RSpec/FactoryBot/AvoidCreate

      def initial_scopes(inputs)
        picker_data = helper.oauth_application_granular_scopes_picker_data(owner, inputs)

        Gitlab::Json::SafeParser.parse(picker_data[:initial_scopes])
      end

      def selected_memberships_inputs(groups, projects)
        [{ access: 'selected_memberships', permissions: ['read_avatar'], group_ids: groups.map { |g| g.id.to_s },
           project_ids: projects.map { |p| p.id.to_s } }]
      end

      it 'upcases the access, keeps the permissions and resolves the namespaces' do
        inputs = [
          { access: 'user', permissions: ['execute_mcp_tool'] },
          { access: 'selected_memberships', permissions: ['read_avatar'], group_ids: [subgroup.id.to_s],
            project_ids: [project.id.to_s] }
        ]

        expect(initial_scopes(inputs)).to eq([
          { 'access' => 'USER', 'permissions' => ['execute_mcp_tool'], 'namespaces' => [] },
          {
            'access' => 'SELECTED_MEMBERSHIPS',
            'permissions' => ['read_avatar'],
            'namespaces' => [
              { 'id' => subgroup.to_global_id.to_s, '__typename' => 'Group', 'name' => 'Widgets',
                'fullPath' => subgroup.full_path },
              { 'id' => project.to_global_id.to_s, '__typename' => 'Project', 'name' => 'Site',
                'fullPath' => project.full_path }
            ]
          }
        ])
      end

      it 'does not resolve namespaces outside the owning group' do
        inputs = [{ access: 'selected_memberships', permissions: ['read_avatar'],
                    group_ids: [outside_group.id.to_s], project_ids: [outside_project.id.to_s] }]

        expect(initial_scopes(inputs))
          .to eq([{ 'access' => 'SELECTED_MEMBERSHIPS', 'permissions' => ['read_avatar'], 'namespaces' => [] }])
      end

      it 'resolves the namespaces without a query per namespace' do
        # Loads the owner's route, which later calls reuse
        initial_scopes(selected_memberships_inputs([subgroup], [project]))

        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          initial_scopes(selected_memberships_inputs([subgroup], [project]))
        end

        expect { initial_scopes(selected_memberships_inputs([subgroup, *more_subgroups], [project, *more_projects])) }
          .to issue_same_number_of_queries_as(control)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(granular_oauth_tokens: false)
      end

      it 'returns nil' do
        expect(helper.oauth_application_granular_scopes_picker_data(group, nil)).to be_nil
      end
    end
  end

  describe '#authorized_record_remote_application' do
    it 'returns the remote application a consent carries' do
      consent = build(:oauth_consent, :cross_cell)
      consent.remote_application = Authn::IamService::RemoteOauthApplication.placeholder(consent.client_id)

      expect(helper.authorized_record_remote_application(consent)).to eq(consent.remote_application)
    end

    it 'is nil for a consent with a local application' do
      expect(helper.authorized_record_remote_application(build(:oauth_consent))).to be_nil
    end

    it 'is nil for a token' do
      expect(helper.authorized_record_remote_application(build(:oauth_access_token))).to be_nil
    end
  end

  describe '#remote_oauth_application_description' do
    let(:application) do
      Authn::IamService::RemoteOauthApplication.new(
        client_id: 'remote-client', name: 'Remote app', owner_label: 'Jane Doe', created_at: 3.days.ago
      )
    end

    subject(:description) { helper.remote_oauth_application_description(application) }

    it 'names the owner and when the application was added' do
      expect(description).to eq('Jane Doe added this OAuth application 3 days ago.')
    end

    context 'when IAM has no owner label' do
      before do
        application.owner_label = nil
      end

      it 'attributes the application to an administrator' do
        expect(description).to eq('An administrator added this OAuth application 3 days ago.')
      end
    end

    context 'when the application was registered dynamically' do
      before do
        application.dynamic = true
      end

      it 'attributes the application to an anonymous service' do
        expect(description).to eq(
          'An anonymous service added this dynamically created OAuth application 3 days ago.'
        )
      end
    end

    context 'when IAM could not be reached' do
      let(:application) { Authn::IamService::RemoteOauthApplication.placeholder('remote-client') }

      it 'says the details are unavailable' do
        expect(description).to eq(s_('AuthorizedApplication|Application details are temporarily unavailable.'))
      end
    end

    context 'when IAM sent no creation time' do
      before do
        application.created_at = nil
      end

      it 'renders no description instead of failing' do
        expect(description).to be_nil
      end
    end
  end
end
