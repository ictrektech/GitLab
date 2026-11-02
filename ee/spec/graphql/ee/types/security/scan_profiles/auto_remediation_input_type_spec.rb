# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::ScanProfiles::AutoRemediationInputType, feature_category: :dependency_management do
  specify { expect(described_class.graphql_name).to eq('SecurityScanProfileAutoRemediationInput') }

  it 'has the expected arguments' do
    expect(described_class.arguments.keys)
      .to match_array(%w[enabled cooldown severityLevel upgradePolicy openMergeRequestsLimit runnerTags])
  end
end
