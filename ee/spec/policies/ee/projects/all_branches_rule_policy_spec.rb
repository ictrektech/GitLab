# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::AllBranchesRulePolicy, feature_category: :source_code_management do
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:project, freeze: false) { create(:project) }

  let(:branch_rule) { Projects::AllBranchesRule.new(project) }

  subject { described_class.new(user, branch_rule) }

  it { is_expected.to delegate_to(::ProjectPolicy) }

  context 'as a guest with admin_protected_branch custom role' do
    let_it_be(:group, freeze: false) { create(:group) }
    let_it_be(:project, freeze: false) { create(:project, group: group) }
    let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }

    let(:branch_rule) { Projects::AllBranchesRule.new(project) }

    before do
      stub_licensed_features(custom_roles: true)
      create(:member_role, :guest, admin_protected_branch: true, namespace: group, members: [project_member])
    end

    it { expect_disallowed(:read_branch_rule) }
    it { expect_disallowed(:delete_branch_rule) }

    context 'when custom_roles feature is not licensed' do
      before do
        stub_licensed_features(custom_roles: false)
      end

      it { expect_disallowed(:read_branch_rule) }
      it { expect_disallowed(:delete_branch_rule) }
    end
  end

  context 'as a guest with manage_merge_request_settings custom role' do
    let_it_be(:group, freeze: false) { create(:group) }
    let_it_be(:project, freeze: false) { create(:project, group: group) }
    let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }

    let(:branch_rule) { Projects::AllBranchesRule.new(project) }

    before do
      stub_licensed_features(custom_roles: true)
      create(:member_role, :guest, :manage_merge_request_settings, namespace: group, members: [project_member])
    end

    it { expect_allowed(:read_branch_rule) }
    it { expect_disallowed(:update_branch_rule) }
    it { expect_allowed(:delete_branch_rule) }

    context 'when custom_roles feature is not licensed' do
      before do
        stub_licensed_features(custom_roles: false)
      end

      it { expect_disallowed(:read_branch_rule) }
      it { expect_disallowed(:delete_branch_rule) }
    end
  end
end
