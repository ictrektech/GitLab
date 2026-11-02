# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'secrets_manager initializer', feature_category: :secrets_management do
  let(:configuration) { SecretsManagement::SecretsManagerClient.configuration }

  it 'configures the client host and base path' do
    expect(configuration.host).to eq('http://127.0.0.1:9800')
    expect(configuration.base_path).to eq('v1')
  end

  it 'configures the client from a to_prepare hook so it survives code reloads' do
    # We assert the initializer registered such a hook, rather than triggering a real
    # reload: Rails.application.reloader.prepare! unloads autoloaded code and clears
    # FactoryBot's definitions when reloading is disabled (CACHE_CLASSES=true, as in CI),
    # leaking into later specs in the shared process.
    expect(Rails.application.config.to_prepare_blocks).to include(
      have_attributes(source_location: [end_with('ee/config/initializers/secrets_manager.rb'), anything])
    )
  end
end
