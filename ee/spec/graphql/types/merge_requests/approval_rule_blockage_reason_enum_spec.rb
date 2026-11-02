# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ApprovalRuleBlockageReasonKind'], feature_category: :code_testing do
  it 'exposes every reason of the coverage approval check' do
    expect(described_class.values.values.map(&:value))
      .to match_array(Gitlab::Ci::CoverageApprovalCheck::REASONS)
  end
end
