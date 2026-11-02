# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MergeRequestRiskAssessmentStatus'], feature_category: :dap_code_review do
  let(:states) { ::MergeRequests::RiskAssessment.state_machines[:status].states }

  it 'exposes all risk assessment states' do
    expect(described_class.values.keys).to match_array(states.map { |state| state.name.to_s.upcase })
  end

  it 'declares the same stored value as the state machine for each state' do
    definition = ::MergeRequests::RiskAssessmentStatus.definition

    states.each do |state|
      expect(definition.dig(state.name, :value)).to eq(state.value)
    end
  end
end
