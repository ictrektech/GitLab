# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'API::Hooks route tiers', feature_category: :webhooks do
  describe API::GroupHooks do
    it 'annotates every route as Premium, including the shared hook modules', :aggregate_failures do
      routes = described_class.routes

      expect(routes.map(&:path)).to include(
        a_string_including('/url_variables/'), a_string_including('/custom_headers/'), a_string_including('/events')
      )
      expect(routes.map { |route| route.settings[:tier] }.uniq).to eq([:premium])
    end
  end
end
