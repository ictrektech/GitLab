# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskContributionKind'], feature_category: :code_review_workflow do
  it 'exposes signal and domain kinds' do
    expect(described_class.values.transform_values(&:value)).to eq('SIGNAL' => 'signal', 'DOMAIN' => 'domain')
  end
end
