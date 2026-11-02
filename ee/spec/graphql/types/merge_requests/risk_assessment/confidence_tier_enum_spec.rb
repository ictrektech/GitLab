# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskConfidenceTier'], feature_category: :code_review_workflow do
  it 'exposes one value for each confidence tier' do
    expect(described_class.values.keys).to contain_exactly('LOW', 'MEDIUM', 'HIGH', 'VERY_HIGH')
  end
end
