# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Catalog::ThirdPartyFlowType, feature_category: :ai_catalog_curation do
  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiCatalogThirdPartyFlow')
  end

  it 'exposes whether a trigger for the flow can carry a goal' do
    expect(described_class).to include_graphql_fields('accepts_trigger_goal')
  end

  it { expect(described_class).to require_graphql_authorizations(:read_ai_catalog_item) }
end
