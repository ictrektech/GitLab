# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::TriageAndRemediationFlowStatusEnum, feature_category: :security_asset_inventories do
  it 'exposes the flow statuses' do
    expect(described_class.values.values.map(&:value))
      .to match_array(%w[not_applicable foundational_flows_disabled flow_unavailable flow_not_enabled available])
  end
end
