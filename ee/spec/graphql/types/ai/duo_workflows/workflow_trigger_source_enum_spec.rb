# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DuoWorkflows::WorkflowTriggerSourceEnum, feature_category: :duo_agent_platform do
  it { expect(described_class.graphql_name).to eq('DuoWorkflowTriggerSource') }

  it 'exposes every trigger_source defined on the model' do
    expect(described_class.values.values.map(&:value))
      .to match_array(::Ai::DuoWorkflows::Workflow.trigger_sources.keys)
  end
end
