# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillUserAdminRolesFromUserMemberRoles,
  migration: :gitlab_main_user,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:namespaces) { table(:namespaces) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }
  let(:user_member_roles) { table(:user_member_roles) }
  let(:user_admin_roles) { table(:user_admin_roles) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }
  let(:user) { create_user('u') }

  # The member_roles trigger is already in place, so this role gets an admin_roles copy.
  let(:admin_role) do
    member_roles.create!(name: 'Admin reader', permissions: { read_admin_users: true },
      organization_id: organization.id)
  end

  let(:namespace_role) do
    member_roles.create!(name: 'Guest plus', base_access_level: 10, permissions: { read_code: true },
      namespace_id: group.id)
  end

  def create_user(username)
    users.create!(
      email: "#{username}@example.com",
      username: username,
      projects_limit: 0,
      organization_id: organization.id
    )
  end

  # Inserts an assignment the way it existed before the sync trigger, with no copy.
  def create_assignment(**attributes)
    user_member_roles.create!(user_id: user.id, **attributes).tap do
      user_admin_roles.where(user_id: user.id).delete_all
    end
  end

  it 'copies assignments to admin roles' do
    assignment = create_assignment(member_role_id: admin_role.id, ldap: true)

    migrate!

    expect(user_admin_roles.find_by!(user_id: user.id).attributes).to eq(
      assignment.reload.attributes.slice('user_id', 'ldap', 'created_at', 'updated_at')
        .merge('admin_role_id' => admin_role.id)
    )
  end

  it 'skips assignments to roles that are not admin roles' do
    create_assignment(member_role_id: namespace_role.id)

    expect { migrate! }.not_to change { user_admin_roles.count }.from(0)
  end

  it 'replaces an existing assignment for the same user' do
    create_assignment(member_role_id: admin_role.id)
    other_admin_role = admin_roles.create!(id: admin_role.id + 1, name: 'Other', permissions: {},
      organization_id: organization.id)
    user_admin_roles.create!(user_id: user.id, admin_role_id: other_admin_role.id)

    migrate!

    expect(user_admin_roles.find_by!(user_id: user.id).admin_role_id).to eq(admin_role.id)
  end
end
