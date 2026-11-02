# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApprovalRules::ApprovalGroupRulePolicy, feature_category: :source_code_management do
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:user) { create(:user, owner_of: group) }
  let_it_be(:approval_rule) { create(:approval_group_rule, group: group) }

  let(:modify_abilities) { %i[create_approval_rule update_approval_rule delete_approval_rule] }

  subject(:permissions) { described_class.new(user, approval_rule) }

  it { is_expected.to delegate_to(GroupPolicy) }

  context 'when the instance-level approval rule lock is enabled' do
    before do
      stub_application_setting(disable_overriding_approvers_per_merge_request: true)
    end

    context 'without the admin_merge_request_approvers_rules license' do
      before do
        stub_licensed_features(admin_merge_request_approvers_rules: false)
      end

      it { expect_allowed(:read_approval_rule, *modify_abilities) }
    end
  end
end
