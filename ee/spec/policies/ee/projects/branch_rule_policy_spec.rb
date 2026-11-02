# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::BranchRulePolicy, feature_category: :source_code_management do
  let_it_be(:protected_branch, freeze: false) { create(:protected_branch) }
  let_it_be(:user) { create(:user, maintainer_of: protected_branch.project) }

  let(:branch_rule) { Projects::BranchRule.new(protected_branch.project, protected_branch) }

  subject(:policy) { described_class.new(user, branch_rule) }

  it { is_expected.to delegate_to(::ProjectPolicy) }

  describe 'Abilities' do
    using RSpec::Parameterized::TableSyntax

    where(
      :unprotect_restrictions_enabled, :can_unprotect, :branch_rule_behavior
    ) do
      true  | true  | 'allows branch rule crud'
      true  | false | 'disallows branch rule changes'
      false | false | 'allows branch rule crud'
      false | true  | 'allows branch rule crud'
    end

    it_behaves_like 'allows branch rule crud'

    with_them do
      before do
        stub_licensed_features(unprotection_restrictions: unprotect_restrictions_enabled)

        allow(protected_branch)
          .to receive(:can_unprotect?).with(user)
          .and_return(can_unprotect)
      end

      it_behaves_like params[:branch_rule_behavior]
    end
  end

  context 'as a guest with admin_protected_branch custom role' do
    let_it_be(:group, freeze: false) { create(:group) }
    let_it_be(:project, freeze: false) { create(:project, group: group) }
    let_it_be(:protected_branch, freeze: false) { create(:protected_branch, project: project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }

    let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }

    before do
      stub_licensed_features(custom_roles: true)
      create(:member_role, :guest, admin_protected_branch: true, namespace: group, members: [project_member])
    end

    it { expect_allowed(:read_branch_rule) }
    it { expect_allowed(:create_branch_rule) }
    it { expect_allowed(:update_branch_rule) }
    it { expect_allowed(:delete_branch_rule) }

    context 'when custom_roles feature is not licensed' do
      before do
        stub_licensed_features(custom_roles: false)
      end

      it_behaves_like 'disallows branch rule crud'
    end
  end

  context 'as a guest with manage_merge_request_settings custom role' do
    let_it_be(:group, freeze: false) { create(:group) }
    let_it_be(:project, freeze: false) { create(:project, group: group) }
    let_it_be(:protected_branch, freeze: false) { create(:protected_branch, project: project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:project_member, freeze: false) { create(:project_member, :guest, user: user, project: project) }

    let(:branch_rule) { Projects::BranchRule.new(project, protected_branch) }

    before do
      stub_licensed_features(custom_roles: true)
      create(:member_role, :guest, :manage_merge_request_settings, namespace: group, members: [project_member])
    end

    it { expect_allowed(:read_branch_rule) }
    it { expect_disallowed(:create_branch_rule) }
    it { expect_disallowed(:update_branch_rule) }
    it { expect_disallowed(:delete_branch_rule) }

    context 'when custom_roles feature is not licensed' do
      before do
        stub_licensed_features(custom_roles: false)
      end

      it_behaves_like 'disallows branch rule crud'
    end
  end
end
