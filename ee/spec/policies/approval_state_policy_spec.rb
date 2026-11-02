# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ApprovalStatePolicy, feature_category: :code_review_workflow do
  let(:user) { build_stubbed(:user) }
  let(:approval_state) { ApprovalState.new(build_stubbed(:merge_request)) }

  subject(:policy) { described_class.new(user, approval_state) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
