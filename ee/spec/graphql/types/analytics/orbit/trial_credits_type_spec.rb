# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Analytics::Orbit::TrialCreditsType, feature_category: :knowledge_graph do
  it { expect(described_class.graphql_name).to eq('OrbitTrialCredits') }
  it { expect(described_class).to have_graphql_fields(:remaining, :total) }
  it { expect(described_class).to require_graphql_authorizations(:read_orbit_trial) }
end
