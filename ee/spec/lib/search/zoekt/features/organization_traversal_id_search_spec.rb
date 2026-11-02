# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::Features::OrganizationTraversalIdSearch, feature_category: :global_search do
  it_behaves_like 'zoekt feature', feature: :organization_traversal_id_search
end
