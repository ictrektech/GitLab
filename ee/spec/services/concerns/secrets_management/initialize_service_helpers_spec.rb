# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::InitializeServiceHelpers, feature_category: :secrets_management do
  let(:service_instance) do
    Class.new do
      include SecretsManagement::InitializeServiceHelpers
    end.new
  end

  describe '#track_enabled_event' do
    it 'raises a NotImplementedError' do
      expect { service_instance.send(:track_enabled_event) }.to raise_error(NotImplementedError)
    end
  end
end
