# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::BusinessContextSecurityGuidelines::Definition,
  feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.business_context_security_guidelines_experimental }

  it 'is named Vulnerability Context Flow' do
    expect(flow.display_name).to eq('Vulnerability Context Flow')
  end

  it 'is gated by the sdlc_context_agent_trigger feature flag' do
    expect(flow.feature_flag).to eq('sdlc_context_agent_trigger')
  end

  it 'has no triggers and supports no trigger events' do
    expect(flow.triggers).to be_empty
    expect(flow.supported_events).to eq([])
  end
end
