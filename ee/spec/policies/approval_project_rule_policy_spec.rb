# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApprovalProjectRulePolicy, feature_category: :code_review_workflow do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be_with_reload(:approval_rule) { create(:approval_project_rule, project: project) }

  let(:modify_abilities) { %i[modify_approvers_rules create_approval_rule update_approval_rule delete_approval_rule] }

  it { expect(described_class.new(project.creator, approval_rule)).to delegate_to(ProjectPolicy) }

  context 'when the instance-level approval rule lock is enabled' do
    let_it_be(:maintainer) { create(:user, maintainer_of: project) }

    let(:user) { maintainer }

    subject { described_class.new(user, approval_rule) }

    before do
      stub_application_setting(disable_overriding_approvers_per_merge_request: true)
    end

    context 'without the admin_merge_request_approvers_rules license' do
      before do
        stub_licensed_features(admin_merge_request_approvers_rules: false)
      end

      it { expect_allowed(*modify_abilities) }
    end
  end

  context 'when a merge request approval policy prevents editing approval rules' do
    let_it_be(:maintainer) { create(:user, maintainer_of: project) }
    let_it_be(:configuration) do
      create(:security_orchestration_policy_configuration, project: project)
    end

    let_it_be(:policy) do
      create(:security_policy,
        :prevent_editing_approval_rules,
        security_orchestration_policy_configuration: configuration,
        linked_projects: [project])
    end

    let(:user) { maintainer }

    subject { described_class.new(user, approval_rule) }

    before do
      stub_licensed_features(admin_merge_request_approvers_rules: true, security_orchestration_policies: true)
    end

    it { expect_allowed(*modify_abilities) }
  end
end
