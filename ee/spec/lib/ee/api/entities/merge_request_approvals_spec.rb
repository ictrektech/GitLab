# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::MergeRequestApprovals, feature_category: :source_code_management do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:approver) { create(:user, developer_of: project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:expected_attributes) do
    %i[
      id
      iid
      project_id
      title
      description
      state
      created_at
      updated_at
      merge_status
      approved
      approvals_required
      approvals_left
      require_password_to_approve
      approved_by
      suggested_approvers
      approvers
      approver_groups
      user_has_approved
      user_can_approve
      approval_rules_left
      has_approval_rules
      merge_request_approvers_available
      multiple_approval_rules_available
      invalid_approvers_rules
    ]
  end

  subject(:representation) { described_class.new(merge_request, current_user: user) }

  before do
    rule = create(:approval_merge_request_rule, merge_request: merge_request, approvals_required: 2)
    rule.users << approver
    create(:approval, merge_request: merge_request, user: approver)
  end

  it 'presents the approval state of the merge request', :aggregate_failures do
    approval_state = API::Entities::ApprovalState.new(merge_request.approval_state, current_user: user)

    expect(representation.as_json).to include(approvals_required: 2, approvals_left: 1)
    expect(representation.to_json).to eq(approval_state.to_json)
  end

  it 'exposes every attribute of the approval state' do
    expect(representation.as_json.keys).to match_array(expected_attributes)
  end
end
