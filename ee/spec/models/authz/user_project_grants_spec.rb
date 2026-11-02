# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::UserProjectGrants, feature_category: :permissions do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be(:root) { create(:group) }
  let_it_be(:project) { create(:project, group: root) }
  let_it_be(:member_role) { create(:member_role, namespace: root) }
  let_it_be(:link_role) { create(:member_role, namespace: root) }

  # Custom roles are set directly, because only their IDs matter here.
  def with_role(record, role)
    record.update_column(:member_role_id, role&.id)
    record
  end

  def grants_for(target = project)
    described_class.new(user.id).for_projects([target.id]).fetch(target.id)
      .map { |grant| [grant.source, grant.access_level, grant.member_role_id] }
  end

  describe 'custom roles on group shares' do
    let_it_be(:invited) { create(:group) }

    where(:member_level, :link_level, :link_has_role, :expected_role) do
      Gitlab::Access::MAINTAINER | Gitlab::Access::DEVELOPER | true  | :link
      Gitlab::Access::REPORTER   | Gitlab::Access::DEVELOPER | true  | :member
      Gitlab::Access::DEVELOPER  | Gitlab::Access::DEVELOPER | false | nil
      Gitlab::Access::DEVELOPER  | Gitlab::Access::DEVELOPER | true  | :member
    end

    with_them do
      it 'follows the side with the lower access level, as Authz::MemberRoleInSharedResource does' do
        link = create(:group_group_link, shared_group: root, shared_with_group: invited, group_access: link_level)
        with_role(link, link_has_role ? link_role : nil)
        with_role(invited.add_member(user, member_level), member_role)

        role_id = { link: link_role.id, member: member_role.id }[expected_role]

        expect(grants_for).to contain_exactly([:group_share, [member_level, link_level].min, role_id])
      end
    end
  end

  describe 'custom roles on project shares' do
    let_it_be(:invited_parent) { create(:group) }
    let_it_be(:invited) { create(:group, parent: invited_parent) }
    let_it_be(:other_project) { create(:project) }

    before_all do
      create(:project_group_link, project: other_project, group: invited, group_access: Gitlab::Access::DEVELOPER)
    end

    it 'takes the custom role from a direct membership of the invited group' do
      with_role(invited.add_reporter(user), member_role)

      expect(grants_for(other_project)).to contain_exactly([:project_share, Gitlab::Access::REPORTER, member_role.id])
    end

    it 'takes no custom role from inherited members of the invited group' do
      with_role(invited_parent.add_reporter(user), member_role)

      expect(grants_for(other_project)).to contain_exactly([:project_share, Gitlab::Access::REPORTER, nil])
    end

    it 'keeps the custom role of a Minimal Access member of the invited group without granting access' do
      with_role(create(:group_member, :minimal_access, group: invited, user: user), member_role)

      expect(grants_for(other_project)).to contain_exactly([:project_share, Gitlab::Access::MINIMAL_ACCESS,
        member_role.id])
      expect(described_class.new(user.id).max_access_levels([other_project.id]))
        .to eq(other_project.id => Gitlab::Access::NO_ACCESS)
    end
  end
end
