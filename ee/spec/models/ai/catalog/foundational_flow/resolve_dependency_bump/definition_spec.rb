# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::ResolveDependencyBump::Definition,
  feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.resolve_dependency_bump_experimental }

  it 'supports the mention trigger' do
    expect(flow.triggers).to include(::Ai::FlowTrigger::EVENT_TYPES[:mention])
  end

  it 'has a goal template' do
    expect(flow.goal_templates).to eq(::Ai::Catalog::GoalTemplates::ResolveDependencyBump)
  end

  it 'allows any event type (supported_events is nil)' do
    expect(flow.supported_events).to be_nil
  end
end
