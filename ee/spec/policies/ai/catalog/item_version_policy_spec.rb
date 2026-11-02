# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemVersionPolicy, :with_current_organization, feature_category: :ai_catalog_curation do
  it { expect(described_class).to delegate_to(Ai::Catalog::ItemPolicy) }
end
