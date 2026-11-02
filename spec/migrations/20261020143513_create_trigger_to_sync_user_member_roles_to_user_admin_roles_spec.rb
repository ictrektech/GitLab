# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe CreateTriggerToSyncUserMemberRolesToUserAdminRoles,
  migration: :gitlab_main_org,
  feature_category: :permissions do
  let(:organizations) { table(:organizations) }
  let(:users) { table(:users) }
  let(:member_roles) { table(:member_roles) }
  let(:admin_roles) { table(:admin_roles) }
  let(:user_member_roles) { table(:user_member_roles) }
  let(:user_admin_roles) { table(:user_admin_roles) }

  let(:organization) { organizations.create!(name: 'org', path: 'org') }
  let(:user) { create_user('u') }
  let(:other_user) { create_user('o') }

  # The member_roles trigger is already in place, so these roles get an admin_roles copy.
  let(:role) { create_admin_member_role('Admin reader') }
  let(:other_role) { create_admin_member_role('Admin auditor') }

  def create_user(username)
    users.create!(
      email: "#{username}@example.com",
      username: username,
      projects_limit: 0,
      organization_id: organization.id
    )
  end

  def create_admin_member_role(name)
    member_roles.create!(name: name, permissions: { read_admin_users: true }, organization_id: organization.id)
  end

  def copied_attributes(assignment)
    assignment.reload.attributes.slice('user_id', 'ldap', 'created_at', 'updated_at')
      .merge('admin_role_id' => assignment.member_role_id)
  end

  before do
    migrate!
  end

  it 'copies a new assignment' do
    assignment = user_member_roles.create!(user_id: user.id, member_role_id: role.id, ldap: true)

    expect(user_admin_roles.find_by!(user_id: user.id).attributes).to eq(copied_attributes(assignment))
  end

  it 'updates the copy when the assignment changes role' do
    assignment = user_member_roles.create!(user_id: user.id, member_role_id: role.id)

    assignment.update!(member_role_id: other_role.id, ldap: true)

    expect(user_admin_roles.find_by!(user_id: user.id).attributes).to eq(copied_attributes(assignment))
  end

  it 'moves the copy when the assignment changes user' do
    assignment = user_member_roles.create!(user_id: user.id, member_role_id: role.id)

    assignment.update!(user_id: other_user.id)

    expect(user_admin_roles.pluck(:user_id)).to contain_exactly(other_user.id)
  end

  it 'deletes the copy when the assignment is deleted' do
    assignment = user_member_roles.create!(user_id: user.id, member_role_id: role.id)

    expect { assignment.delete }.to change { user_admin_roles.count }.from(1).to(0)
  end

  it 'deletes the copy when the role is deleted' do
    user_member_roles.create!(user_id: user.id, member_role_id: role.id)

    expect { role.delete }.to change { user_admin_roles.count }.from(1).to(0)
  end

  context 'when the role has no admin_roles copy yet' do
    before do
      admin_roles.where(id: other_role.id).delete_all
    end

    it 'skips the assignment' do
      expect { user_member_roles.create!(user_id: user.id, member_role_id: other_role.id) }
        .to change { user_member_roles.count }.by(1)
        .and not_change { user_admin_roles.count }
    end

    it 'deletes the copy when the assignment moves to that role' do
      assignment = user_member_roles.create!(user_id: user.id, member_role_id: role.id)

      expect { assignment.update!(member_role_id: other_role.id) }
        .to change { user_admin_roles.count }.from(1).to(0)
    end

    it 'keeps an assignment to another admin role when the assignment is deleted' do
      assignment = user_member_roles.create!(user_id: user.id, member_role_id: other_role.id)
      user_admin_roles.create!(user_id: user.id, admin_role_id: role.id)

      expect { assignment.delete }.not_to change { user_admin_roles.count }.from(1)
    end
  end
end
