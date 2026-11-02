# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillAdminRolesFromMemberRoles,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }

  let!(:admin_role) do
    member_roles.create!(name: 'Admin reader', permissions: { read_admin_users: true },
      organization_id: organization.id)
  end

  let!(:namespace_role) do
    member_roles.create!(name: 'Guest plus', base_access_level: 10, permissions: { read_code: true },
      namespace_id: group.id)
  end

  let!(:instance_role) do
    member_roles.create!(name: 'Instance guest plus', base_access_level: 10, permissions: { read_code: true },
      organization_id: organization.id)
  end

  def role_attributes(role)
    role.reload.attributes.slice('id', 'name', 'description', 'permissions', 'organization_id', 'created_at',
      'updated_at')
  end

  # Existing roles were created before the sync trigger, so they have no copies yet.
  before do
    admin_roles.delete_all
  end

  it 'copies admin roles keeping their IDs' do
    migrate!

    expect(admin_roles.all.map { |role| role_attributes(role) }).to contain_exactly(role_attributes(admin_role))
  end

  it 'updates a copy that does not match its role' do
    admin_roles.create!(id: admin_role.id, name: 'Old name', permissions: {}, organization_id: organization.id)

    migrate!

    expect(role_attributes(admin_roles.find(admin_role.id)).except('created_at'))
      .to eq(role_attributes(admin_role).except('created_at'))
  end
end
