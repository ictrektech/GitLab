# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User with the `archive_subgroup` custom ability', feature_category: :groups_and_projects do
  include ApiHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:role) { create(:member_role, :guest, namespace: group, archive_subgroup: true) }
  let_it_be(:member) { create(:group_member, :guest, member_role: role, user: user, group: group) }
  let_it_be_with_reload(:subgroup) { create(:group, parent: group) }
  let_it_be_with_reload(:archived_subgroup) { create(:group, :archived, parent: group) }

  before do
    stub_licensed_features(custom_roles: true)
  end

  describe API::Groups do
    describe '#archive' do
      it 'user can archive the subgroup' do
        post api("/groups/#{subgroup.id}/archive", user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(subgroup.namespace_settings.reload.archived).to be(true)
      end
    end

    describe '#unarchive' do
      it 'user can unarchive the subgroup' do
        post api("/groups/#{archived_subgroup.id}/unarchive", user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(archived_subgroup.namespace_settings.reload.archived).to be(false)
      end
    end

    describe '#archive the top-level group' do
      it 'user cannot archive the group the role is assigned to' do
        post api("/groups/#{group.id}/archive", user)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(group.namespace_settings.reload.archived).to be(false)
      end
    end

    describe '#delete' do
      it 'user cannot delete the subgroup' do
        delete api("/groups/#{subgroup.id}", user)

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(subgroup.reload).not_to be_self_deletion_scheduled
      end
    end
  end
end
