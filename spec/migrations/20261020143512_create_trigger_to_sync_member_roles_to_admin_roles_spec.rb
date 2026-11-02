# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe CreateTriggerToSyncMemberRolesToAdminRoles, migration: :gitlab_main_org, feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }

  def create_admin_member_role(name)
    member_roles.create!(
      name: name,
      description: "#{name} description",
      permissions: { read_admin_users: true },
      organization_id: organization.id
    )
  end

  def copied_attributes(role)
    role.reload.attributes
      .slice('id', 'name', 'description', 'permissions', 'organization_id', 'created_at', 'updated_at')
  end

  context 'when an admin role is created' do
    before do
      migrate!
    end

    it 'copies the role with the same ID' do
      role = create_admin_member_role('Admin reader')

      expect(admin_roles.find(role.id).attributes).to eq(copied_attributes(role))
    end
  end

  context 'when a non-admin role is created' do
    let(:namespace) do
      namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id)
    end

    before do
      migrate!
    end

    it 'does not copy the role' do
      member_roles.create!(
        name: 'Custom guest',
        base_access_level: Gitlab::Access::GUEST,
        permissions: { read_code: true },
        namespace_id: namespace.id
      )

      expect(admin_roles.count).to eq(0)
    end

    it 'does not copy a namespace role without a base access level' do
      member_roles.create!(name: 'Broken', permissions: { read_code: true }, namespace_id: namespace.id)

      expect(admin_roles.count).to eq(0)
    end

    it 'keeps an admin role with the same ID when the role is updated or deleted' do
      role = member_roles.create!(
        name: 'Custom guest',
        base_access_level: Gitlab::Access::GUEST,
        permissions: { read_code: true },
        namespace_id: namespace.id
      )
      admin_roles.create!(id: role.id, name: 'Other', permissions: {}, organization_id: organization.id)

      role.update!(name: 'Renamed')
      role.delete

      expect(admin_roles.exists?(role.id)).to be(true)
    end
  end

  context 'when an admin role is updated' do
    let!(:role) { create_admin_member_role('Admin reader') }

    before do
      migrate!
    end

    it 'updates the copy' do
      role.update!(name: 'Renamed')
      role.update!(description: 'New', permissions: { read_admin_cicd: true })

      expect(admin_roles.find(role.id).attributes).to eq(copied_attributes(role))
    end

    it 'deletes the copy when the role gets a base access level' do
      role.update!(name: 'Renamed')

      expect { role.update!(base_access_level: Gitlab::Access::GUEST) }
        .to change { admin_roles.count }.from(1).to(0)
    end

    it 'copies a role created before the trigger' do
      expect { role.update!(name: 'Renamed') }.to change { admin_roles.count }.from(0).to(1)
    end
  end

  context 'when an admin role is deleted' do
    before do
      migrate!
    end

    it 'deletes the copy' do
      role = create_admin_member_role('Admin reader')

      expect { role.delete }.to change { admin_roles.count }.from(1).to(0)
    end
  end
end
