# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AiCatalogGroupItemEnabledBy'], feature_category: :ai_catalog_curation do
  it 'exposes the ways an item can be enabled in a group' do
    expect(described_class.values.keys).to match_array(%w[INHERITANCE PROJECT_DIRECT])
  end
end
