# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Analytics::Orbit::TrialStateEnum, feature_category: :knowledge_graph do
  it { expect(described_class.graphql_name).to eq('OrbitTrialState') }
  it { expect(described_class.values.keys).to contain_exactly('ELIGIBLE', 'NOT_ELIGIBLE', 'ACTIVE', 'ENDED') }
end
