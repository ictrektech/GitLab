# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems, feature_category: :portfolio_management do
  describe 'EE_ONLY_FEATURE_NAMES' do
    # CE cannot see EE features, so when a new EE-only feature is exposed it must also be added
    # to the constant or CE will reject it with a 400.
    it 'lists exactly the features that only EE exposes' do
      ce_feature_names = Class.new(Grape::Entity) { include ::API::Entities::WorkItems::Features::CommonExposures }
        .root_exposures.map { |exposure| exposure.key.to_s }

      expect(described_class::EE_ONLY_FEATURE_NAMES)
        .to match_array(described_class::FEATURE_SUPPORTED_VALUES - ce_feature_names)
    end
  end
end
