# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BranchesHelper, feature_category: :source_code_management do
  describe '#access_levels_data' do
    subject(:access_levels_data) { helper.access_levels_data(access_levels) }

    context 'when access_levels is nil' do
      let(:access_levels) { nil }

      it { is_expected.to be_empty }
    end

    context 'when access levels are provided' do
      let(:group) { build_stubbed(:group) }
      let(:project) { build_stubbed(:project) }
      let(:protected_branch) { build_stubbed(:protected_branch, project: project) }
      let(:user) { build_stubbed(:user) }
      let(:deploy_key) { build_stubbed(:deploy_key, user: user) }

      let(:merge_level) do
        build_stubbed(:protected_branch_merge_access_level, protected_branch: protected_branch,
          access_level: Gitlab::Access::DEVELOPER)
      end

      let(:push_level) do
        build_stubbed(:protected_branch_push_access_level, protected_branch: protected_branch,
          access_level: Gitlab::Access::MAINTAINER)
      end

      let(:deploy_key_push_level) do
        build_stubbed(:protected_branch_push_access_level, protected_branch: protected_branch, deploy_key: deploy_key)
      end

      let(:user_push_level) do
        build_stubbed(:protected_branch_push_access_level, protected_branch: protected_branch, user: user)
      end

      let(:group_push_level) do
        build_stubbed(:protected_branch_push_access_level, protected_branch: protected_branch, group: group)
      end

      let(:access_levels) { [merge_level, push_level, deploy_key_push_level, user_push_level, group_push_level] }

      it 'returns the correct array' do
        expected_array = [
          { id: merge_level.id, type: :role, access_level: Gitlab::Access::DEVELOPER },
          { id: push_level.id, type: :role, access_level: Gitlab::Access::MAINTAINER },
          { id: deploy_key_push_level.id, type: :deploy_key, deploy_key_id: deploy_key.id },
          { id: user_push_level.id, type: :user, user_id: user.id, username: user.username, name: user.name, avatar_url: user.avatar_url },
          { id: group_push_level.id, type: :group, group_id: group.id }
        ]

        expect(access_levels_data).to eq(expected_array)
      end

      context 'with a member_role access level' do
        let(:root_group) { build_stubbed(:group) }
        let(:project_with_group) { build_stubbed(:project, group: root_group) }
        let(:protected_branch_with_group) { build_stubbed(:protected_branch, project: project_with_group) }
        let(:member_role) { build_stubbed(:member_role, namespace: root_group) }
        let(:member_role_push_level) do
          build_stubbed(:protected_branch_push_access_level, protected_branch: protected_branch_with_group,
            member_role: member_role)
        end

        let(:access_levels) { [member_role_push_level] }

        before do
          stub_licensed_features(custom_roles: true)
        end

        it 'returns id, type :member_role, and member_role_id' do
          expect(access_levels_data).to eq([
            { id: member_role_push_level.id, type: :member_role, member_role_id: member_role.id }
          ])
        end
      end
    end
  end

  describe '#preselected_push_access_levels_data' do
    subject(:preselected_push_access_levels_data) do
      helper.preselected_push_access_levels_data(access_levels, can_push)
    end

    let(:access_levels) { [instance_double(ProtectedBranch::PushAccessLevel)] }

    context 'when can_push is false' do
      let(:can_push) { false }

      it { is_expected.to contain_exactly(id: nil, type: :role, access_level: Gitlab::Access::NO_ACCESS) }
    end

    context 'when can_push is true' do
      let(:can_push) { true }

      it 'calls access_levels_data method' do
        expect(helper).to receive(:access_levels_data).with(access_levels)

        preselected_push_access_levels_data
      end
    end
  end
end
