# frozen_string_literal: true

RSpec.shared_context 'with Artifact Registry fixture setup' do
  before do
    stub_config(artifact_registry: { api_url: base_url })

    allow_next_instance_of(::ArtifactRegistry::TokenExchange) do |token_exchange|
      allow(token_exchange).to receive(:token_for).and_return('ar-fixture-credential')
    end
  end
end
