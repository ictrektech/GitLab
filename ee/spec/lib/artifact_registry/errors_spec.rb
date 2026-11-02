# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Errors, :aggregate_failures, feature_category: :artifact_registry do
  describe ArtifactRegistry::Errors::Error do
    it 'carries a status and request_id' do
      error = described_class.new('boom', status: 503, request_id: 'req-1')

      expect(error).to have_attributes(message: 'boom', status: 503, request_id: 'req-1')
    end
  end

  describe ArtifactRegistry::Errors::ApiError do
    it 'carries a code and details alongside the base attributes' do
      error = described_class.new('boom', status: 400, code: 'invalid', request_id: 'req-1', details: { a: 1 })

      expect(error).to have_attributes(
        message: 'boom', status: 400, code: 'invalid', request_id: 'req-1', details: { a: 1 }
      )
    end
  end

  describe 'the hierarchy' do
    it 'roots every error at Errors::Error' do
      expect(described_class::AuthorizationError).to be < ArtifactRegistry::Errors::Error
      expect(described_class::UnavailableError).to be < ArtifactRegistry::Errors::Error
      expect(described_class::ConfigurationError).to be < ArtifactRegistry::Errors::Error
      expect(described_class::ApiError).to be < ArtifactRegistry::Errors::Error
    end
  end
end
