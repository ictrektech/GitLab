# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SecretsFpDetection::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.secrets_fp_detection_v1 }

  it 'disallows event triggers' do
    expect(flow.supported_events).to eq([])
  end
end
