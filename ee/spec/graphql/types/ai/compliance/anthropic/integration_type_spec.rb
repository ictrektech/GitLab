# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Compliance::Anthropic::IntegrationType, feature_category: :ai_governance do
  it { expect(described_class.graphql_name).to eq('AnthropicComplianceIntegration') }
  it { expect(described_class).to require_graphql_authorizations(:read_anthropic_compliance_integration) }

  it 'exposes the integration state but not the key' do
    expect(described_class).to have_graphql_fields(:enabled, :disabled_reason, :last_successful_sync_at, :updated_at)
  end
end
