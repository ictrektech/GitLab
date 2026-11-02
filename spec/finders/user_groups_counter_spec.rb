# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UserGroupsCounter, feature_category: :groups_and_projects do
  subject(:group_counts) { described_class.new(user_ids).execute }

  describe '#execute' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group1) { create(:group) }
    let_it_be(:group_member1) do
      create(:group_member, source: group1, user_id: user.id, access_level: Gitlab::Access::OWNER)
    end

    let_it_be(:user_ids) { [user.id] }

    it 'returns authorized group count for the user' do
      expect(group_counts[user.id]).to eq(1)
    end

    context 'when request to join group is pending' do
      let_it_be(:pending_group) { create(:group) }
      let_it_be(:pending_group_member) do
        create(:group_member, requested_at: Time.current.utc, source: pending_group, user_id: user.id)
      end

      it 'does not include pending group in the count' do
        expect(group_counts[user.id]).to eq(1)
      end
    end

    context 'when user is part of sub group' do
      let_it_be(:sub_group) { create(:group, parent: create(:group)) }
      let_it_be(:sub_group_member1) do
        create(:group_member, source: sub_group, user_id: user.id, access_level: Gitlab::Access::DEVELOPER)
      end

      it 'includes sub group in the count' do
        expect(group_counts[user.id]).to eq(2)
      end
    end

    context 'when user is part of namespaced project' do
      let_it_be(:project) { create(:project, group: create(:group)) }
      let_it_be(:project_member) do
        create(:project_member, source: project, user_id: user.id, access_level: Gitlab::Access::REPORTER)
      end

      it 'includes the project group' do
        expect(group_counts[user.id]).to eq(2)
      end
    end

    context 'when user has access through both group membership and project authorization' do
      let_it_be(:shared_group) { create(:group) }
      let_it_be(:shared_project) { create(:project, group: shared_group) }
      let_it_be(:shared_group_member) do
        create(:group_member, source: shared_group, user_id: user.id, access_level: Gitlab::Access::DEVELOPER)
      end

      let_it_be(:shared_project_member) do
        create(:project_member, source: shared_project, user_id: user.id, access_level: Gitlab::Access::DEVELOPER)
      end

      it 'counts the shared group only once' do
        expect(group_counts[user.id]).to eq(2)
      end
    end

    context 'when multiple user IDs are provided' do
      let_it_be(:user2) { create(:user) }
      let_it_be(:project2) { create(:project, group: create(:group)) }
      let_it_be(:project_member2) do
        create(:project_member, source: project2, user_id: user2.id, access_level: Gitlab::Access::REPORTER)
      end

      let_it_be(:user_ids) { [user.id, user2.id] }

      it 'returns counts for each user' do
        expect(group_counts).to eq({ user.id => 1, user2.id => 1 })
      end
    end

    context 'when an organization is given' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:organization_group) { create(:group, organization: organization, developers: user) }
      let_it_be(:organization_project) do
        create(:project, group: create(:group, organization: organization), developers: user)
      end

      subject(:organization_group_counts) { described_class.new(user_ids, organization: organization).execute }

      it 'counts only groups in the organization' do
        expect(organization_group_counts[user.id]).to eq(2)
      end
    end
  end
end
