# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VirtualRegistries::Policies::GroupPolicy, feature_category: :virtual_registry do
  include_context 'GroupPolicy context'
  using RSpec::Parameterized::TableSyntax

  let_it_be(:subgroup) { create(:group, parent: group, visibility_level: group.visibility_level) }
  let(:policy_subject) { ::VirtualRegistries::Policies::Group.new(group) }

  subject { described_class.new(current_user, policy_subject) }

  describe 'delegation' do
    let(:current_user) { owner }

    it { is_expected.to delegate_to(GroupPolicy) }
  end

  describe 'read_virtual_registry' do
    where(:group_visibility) { %w[PUBLIC INTERNAL PRIVATE] }

    with_them do
      let(:current_user) { nil }

      before do
        group.update!(visibility_level: Gitlab::VisibilityLevel.const_get(group_visibility, false))
      end

      it { expect_disallowed(:read_virtual_registry) }
    end

    context 'for deploy token' do
      let(:deploy_token) { create(:deploy_token, :group, groups: [target]) }
      let(:current_user) { deploy_token }

      where(:target, :group_visibility, :read_virtual_registry, :allowed?) do
        ref(:group) | 'PUBLIC'   | true  | true
        ref(:group) | 'PUBLIC'   | false | false
        ref(:group) | 'INTERNAL' | true  | true
        ref(:group) | 'INTERNAL' | false | false
        ref(:group) | 'PRIVATE'  | true  | true
        ref(:group) | 'PRIVATE'  | false | false

        ref(:subgroup) | 'PUBLIC'   | true  | false
        ref(:subgroup) | 'PUBLIC'   | false | false
        ref(:subgroup) | 'INTERNAL' | true  | false
        ref(:subgroup) | 'INTERNAL' | false | false
        ref(:subgroup) | 'PRIVATE'  | true  | false
        ref(:subgroup) | 'PRIVATE'  | false | false
      end

      with_them do
        before do
          deploy_token.read_virtual_registry = read_virtual_registry
          group.update!(visibility_level: Gitlab::VisibilityLevel.const_get(group_visibility, false))
        end

        it { is_expected.to public_send(allowed? ? :be_allowed : :be_disallowed, :read_virtual_registry) }
      end
    end
  end

  context 'for admin when admin mode is disabled' do
    let(:current_user) { admin }

    it 'disallows virtual registry permissions' do
      expect_disallowed(:read_virtual_registry, :create_virtual_registry, :update_virtual_registry,
        :destroy_virtual_registry, :admin_virtual_registry)
    end
  end

  describe 'subgroups' do
    let_it_be(:policy_subject) { ::VirtualRegistries::Policies::Group.new(subgroup) }
    let_it_be(:current_user) { create(:user, owner_of: [group, subgroup]) }

    it 'disallows virtual registry permissions' do
      expect_disallowed(:read_virtual_registry, :create_virtual_registry, :update_virtual_registry,
        :admin_virtual_registry, :destroy_virtual_registry, :read_virtual_registry_setting,
        :update_virtual_registry_setting, :create_virtual_registry_cleanup_policy,
        :read_virtual_registry_cleanup_policy, :update_virtual_registry_cleanup_policy,
        :delete_virtual_registry_cleanup_policy)
    end
  end

  describe 'custom role with read_virtual_registry ability' do
    let_it_be(:custom_role_user, freeze: false) { create(:user) }
    let(:current_user) { custom_role_user }

    before do
      stub_licensed_features(custom_roles: true)
    end

    context 'when the ability is enabled' do
      before do
        member_role = create(:member_role, :minimal_access, read_virtual_registry: true, namespace: group)
        membership = create(:group_member, :minimal_access, user: custom_role_user, source: group,
          member_role: member_role)
        ::Authz::UserGroupMemberRoles::UpdateForGroupService.new(membership).execute
      end

      it { expect_allowed(:read_virtual_registry) }
    end

    context 'when the ability is disabled' do
      before do
        create(:group_member, :minimal_access, user: custom_role_user, source: group)
      end

      it { expect_disallowed(:read_virtual_registry) }
    end
  end
end
