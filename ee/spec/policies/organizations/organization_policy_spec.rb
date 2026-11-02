# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationPolicy, feature_category: :system_access do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:organization) { create(:organization) }

  let_it_be(:owner) { create(:user) }
  let_it_be(:guest) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:admin) { create(:user, :admin) }

  let(:current_user) { non_member }

  subject(:policy) { described_class.new(current_user, organization) }

  before_all do
    create(:organization_user, :owner, organization: organization, user: owner)
    create(:organization_user, organization: organization, user: guest, access_level: :default)
  end

  RSpec.shared_context 'with licensed features' do |features|
    before do
      stub_licensed_features(features)
    end
  end

  it { expect_disallowed(:read_dependency, :read_licenses) }

  describe 'read_organization_analytics' do
    context 'when the user is an admin' do
      let(:current_user) { admin }

      context 'when admin mode is disabled' do
        it { expect_disallowed(:read_organization_analytics) }
      end
    end

    context 'when the user is not a member of the organization' do
      let(:current_user) { non_member }

      it { expect_disallowed(:read_organization_analytics) }
    end

    context 'when the user is anonymous' do
      let(:current_user) { nil }

      it { expect_disallowed(:read_organization_analytics) }
    end
  end

  # Artifact Admins get this through Authz::ArtifactRegistry::AccessManagerCheckService, not the policy.
  describe 'create_artifact_registry_role_assignment' do
    context 'when the user is an organization owner' do
      let(:current_user) { owner }

      it { expect_allowed(:create_artifact_registry_role_assignment) }
    end

    context 'when the user is an organization member who is not an owner' do
      let(:current_user) { guest }

      it { expect_disallowed(:create_artifact_registry_role_assignment) }
    end

    context 'when the user is not a member of the organization' do
      let(:current_user) { non_member }

      it { expect_disallowed(:create_artifact_registry_role_assignment) }
    end

    context 'when the user is an instance admin', :enable_admin_mode do
      let(:current_user) { admin }

      it { expect_disallowed(:create_artifact_registry_role_assignment) }
    end

    context 'when the user is anonymous' do
      let(:current_user) { nil }

      it { expect_disallowed(:create_artifact_registry_role_assignment) }
    end
  end

  describe 'read_user_access_level' do
    context 'when the user is an admin without admin mode' do
      let(:current_user) { admin }

      it { expect_disallowed(:read_user_access_level) }
    end

    context 'when the user is not a member of the organization' do
      let(:current_user) { non_member }

      it { expect_disallowed(:read_user_access_level) }
    end

    context 'when the user is anonymous' do
      let(:current_user) { nil }

      it { expect_disallowed(:read_user_access_level) }
    end
  end

  context 'when the user is an admin' do
    let(:current_user) { admin }

    context 'when admin mode is enabled', :enable_admin_mode do
      it { expect_disallowed(:read_dependency, :read_licenses) }
    end

    context 'when admin mode is disabled' do
      it { expect_disallowed(:read_dependency, :read_licenses) }
    end
  end

  context 'when the user is an organization guest' do
    let(:current_user) { guest }

    it { expect_disallowed(:read_dependency, :read_licenses) }
  end

  describe 'security dashboard permissions' do
    context 'when security dashboard is licensed' do
      include_context 'with licensed features', security_dashboard: true

      context 'when the user is not a member of the organization' do
        let(:current_user) { non_member }

        it { expect_disallowed(:read_security_resource) }
      end

      context 'when the user is an admin without admin mode' do
        let(:current_user) { admin }

        it { expect_disallowed(:read_security_resource) }
      end
    end

    context 'when security dashboard is not licensed' do
      let(:current_user) { owner }

      it { expect_disallowed(:read_security_resource) }
    end
  end

  describe 'configurable work item types permissions' do
    let(:type_actions) { %i[create_work_item_type update_work_item_type] }
    let(:settings_actions) { %i[read_work_item_setting update_work_item_setting] }
    let(:actions) { type_actions + settings_actions }

    before do
      stub_licensed_features(configurable_work_item_types: true)
    end

    it { expect_disallowed(*actions) }

    context 'when user is admin' do
      let(:current_user) { admin }

      it { expect_disallowed(*actions) }
    end

    context 'when user is organization owner' do
      let(:current_user) { owner }

      context 'when configurable work item types is not licensed' do
        before do
          stub_licensed_features(configurable_work_item_types: false)
        end

        it { expect_disallowed(*actions) }
      end
    end
  end

  describe 'custom dashboard permissions' do
    it { expect_disallowed(:read_system_dashboard, :read_custom_dashboard, :create_custom_dashboard) }

    context 'when user is organization owner' do
      let(:current_user) { owner }

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(custom_dashboard_storage: false)
        end

        it 'only allows reading system dashboards' do
          expect_allowed(:read_system_dashboard)
          expect_disallowed(:read_custom_dashboard, :create_custom_dashboard)
        end
      end

      context 'when the feature flag is enabled only for this user' do
        before do
          stub_feature_flags(custom_dashboard_storage: owner)
        end

        it { expect_allowed(:read_custom_dashboard, :create_custom_dashboard) }
      end

      context 'when the feature flag is enabled only for a different user' do
        before do
          stub_feature_flags(custom_dashboard_storage: create(:user))
        end

        it { expect_disallowed(:read_custom_dashboard, :create_custom_dashboard) }
      end
    end

    context 'when user is organization member' do
      let(:current_user) { guest }

      context 'when feature flag is disabled' do
        before do
          stub_feature_flags(custom_dashboard_storage: false)
        end

        it 'only allows reading system dashboards' do
          expect_allowed(:read_system_dashboard)
          expect_disallowed(:read_custom_dashboard, :create_custom_dashboard)
        end
      end
    end

    context 'when user is an admin' do
      let(:current_user) { admin }

      context 'when admin mode is disabled' do
        it { expect_disallowed(:read_system_dashboard, :read_custom_dashboard, :create_custom_dashboard) }
      end

      context 'when admin mode is enabled and the feature flag is disabled', :enable_admin_mode do
        before do
          stub_feature_flags(custom_dashboard_storage: false)
        end

        it { expect_disallowed(:read_custom_dashboard, :create_custom_dashboard) }
      end
    end
  end

  describe 'read_subscription_usage', :saas do
    context 'when the organization is linked to a subscription' do
      before do
        create(:organization_gitlab_subscription, organization: organization)
      end

      context 'when the user is an owner' do
        let(:current_user) { owner }

        it { expect_allowed(:read_subscription_usage) }
      end

      context 'when organization_billing is disabled' do
        let(:current_user) { owner }

        before do
          stub_feature_flags(organization_billing: false)
        end

        it { expect_disallowed(:read_subscription_usage) }
      end

      context 'when organization_billing is enabled only for a different organization' do
        let(:current_user) { owner }

        before do
          stub_feature_flags(organization_billing: create(:organization))
        end

        it { expect_disallowed(:read_subscription_usage) }
      end
    end

    context 'when the organization is not linked to a subscription' do
      let(:current_user) { owner }

      it { expect_disallowed(:read_subscription_usage) }
    end
  end

  describe 'govern_policy abilities' do
    let(:abilities) { %i[read_govern_policy create_govern_policy update_govern_policy delete_govern_policy] }

    context 'when the user is not a member of the organization' do
      let(:current_user) { non_member }

      it { expect_disallowed(*abilities) }
    end

    context 'when the user is anonymous' do
      let(:current_user) { nil }

      it { expect_disallowed(*abilities) }
    end
  end

  describe 'cd abilities' do
    let(:cd_abilities) do
      %i[
        create_cd_application
        create_cd_application_flow_definition
        create_cd_application_link
        create_cd_artifact_source
        create_cd_environment
        create_cd_rollout
        create_cd_service
        create_cd_version_set
        delete_cd_application_link
        read_cd_application
        read_cd_application_flow_definition
        read_cd_application_link
        read_cd_artifact_source
        read_cd_environment
        read_cd_rollout
        read_cd_service
        read_cd_version_set
        resolve_cd_rollout_gate
        update_cd_application
        update_cd_application_link
        update_cd_environment
        update_cd_service
      ]
    end

    context 'when the user is not a member of the organization' do
      let(:current_user) { non_member }

      it { expect_disallowed(*cd_abilities) }
    end

    context 'when the user is an organization member' do
      let(:current_user) { guest }

      it { expect_disallowed(*cd_abilities) }
    end

    context 'when the user is an organization owner' do
      let(:current_user) { owner }

      it { expect_allowed(*cd_abilities) }
    end

    context 'when the user is an admin' do
      let(:current_user) { admin }

      context 'when admin mode is enabled', :enable_admin_mode do
        it { expect_allowed(*cd_abilities) }
      end

      context 'when admin mode is disabled' do
        it { expect_disallowed(*cd_abilities) }
      end
    end
  end
end
