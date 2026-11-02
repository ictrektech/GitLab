# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequestDiffPolicy, feature_category: :code_review_workflow do
  let(:user) { build_stubbed(:user) }
  let(:merge_request_diff) { build_stubbed(:merge_request_diff) }

  subject(:policy) { described_class.new(user, merge_request_diff) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
