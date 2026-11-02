# frozen_string_literal: true

require 'fast_spec_helper'
require 'gitlab/safe_request_store'

RSpec.describe Search::Zoekt::Logger, feature_category: :global_search do
  describe '.build' do
    it 'builds an instance' do
      expect(described_class.build).to be_an_instance_of(described_class)
    end
  end
end
