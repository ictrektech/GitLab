# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::AiSuggestedReviewerPolicy, feature_category: :code_review_workflow do
  let(:user) { build_stubbed(:user) }
  let(:suggestion) { build_stubbed(:ai_suggested_reviewer) }

  subject(:policy) { described_class.new(user, suggestion) }

  it { is_expected.to delegate_to(UserPolicy) }
end
