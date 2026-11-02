# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::AdminRole, feature_category: :permissions do
  subject(:admin_role) { build(:admin_role) }

  describe 'associations' do
    it { is_expected.to have_many(:users) }
    it { is_expected.to have_many(:user_admin_roles) }
  end

  describe 'validation' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:organization_id) }

    context 'for json schema' do
      let(:permissions) { { read_admin_users: true } }

      it { is_expected.to allow_value(permissions).for(:permissions) }

      context 'when trying to store an unsupported value' do
        let(:permissions) { { read_admin_users: 'some_value' } }

        it { is_expected.not_to allow_value(permissions).for(:permissions) }
      end
    end

    context 'for permissions' do
      it 'removes disabled permissions' do
        admin_role = build(:admin_role)
        admin_role.permissions["nonexistent"] = false

        expect { admin_role.validate }.to change { admin_role.permissions }.from(
          { 'read_admin_users' => true, 'nonexistent' => false }
        ).to({ 'read_admin_users' => true })
      end

      it 'returns an error when no permissions are enabled' do
        admin_role = build(:admin_role)
        admin_role.permissions["read_admin_users"] = false

        admin_role.validate
        expect(admin_role.errors[:base]).to eq(['Cannot create a member role with no enabled permissions'])
      end

      it 'returns an error for member role permissions' do
        admin_role = build(:admin_role)
        admin_role.permissions["read_code"] = true

        admin_role.validate
        expect(admin_role.errors.first.message).to eq('Unknown permission: read_code')
      end

      it 'returns an error for each unknown permission' do
        admin_role = build(:admin_role)
        admin_role.permissions["unknown1"] = true
        admin_role.permissions["unknown2"] = true

        admin_role.validate
        expect(admin_role.errors.messages[:base]).to match_array(
          ['Unknown permission: unknown1', 'Unknown permission: unknown2']
        )
      end
    end
  end

  describe 'callbacks' do
    let_it_be_with_reload(:admin_role) { create(:admin_role) }

    it 'allows deletion without any user associated' do
      expect(admin_role.destroy).to be_truthy
    end

    it 'prevent deletion when user is associated' do
      create(:user_admin_role, admin_role: admin_role)

      admin_role.user_admin_roles.reload

      expect(admin_role.destroy).to be_falsey
      expect(admin_role.errors.messages[:base]).to(include(
        s_('MemberRole|Admin role is assigned to one or more users. Remove role from all users, then delete role.')
      ))
    end
  end

  describe '#enabled_permissions' do
    let(:admin_role) { build(:admin_role, *permissions.keys) }

    subject { admin_role.enabled_permissions }

    context 'when some permissions are enabled' do
      let(:permissions) { Gitlab::CustomRoles::Definition.admin.to_a.sample(3).to_h }

      it { is_expected.to match_array(permissions) }
    end
  end

  describe 'admin_related_role?' do
    subject(:admin_related_role) { admin_role.admin_related_role? }

    it { is_expected.to be true }
  end
end
