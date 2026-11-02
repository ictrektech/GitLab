# frozen_string_literal: true

require 'fast_spec_helper'
require 'gitlab/http_v2'

RSpec.describe Gitlab::SubscriptionPortal::SecretsManagerResponseError, feature_category: :secrets_management do
  # The resolver and the mutations rescue this class and check for UnavailableError, so
  # both the per-endpoint Error classes and the shared UnavailableError must sit under it.
  describe 'hierarchy' do
    it 'is the ancestor of the per-endpoint Error classes and of UnavailableError', :aggregate_failures do
      expect(described_class.superclass).to eq(Gitlab::SubscriptionPortal::CdotResponseError)
      expect(Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error.superclass).to eq(described_class)
      expect(Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error.superclass)
        .to eq(described_class)
      expect(described_class::UnavailableError.superclass).to eq(described_class)
    end

    it 'is the UnavailableError of both endpoints', :aggregate_failures do
      expect(Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::UnavailableError)
        .to eq(described_class::UnavailableError)
      expect(Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::UnavailableError)
        .to eq(described_class::UnavailableError)
    end
  end
end
