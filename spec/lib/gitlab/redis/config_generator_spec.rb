# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Redis::ConfigGenerator, feature_category: :redis do
  describe '.parse_credentials_provider' do
    it 'converts a Hash provider config into a callable password and descriptor' do
      config = {
        url: 'rediss://cache.example.com',
        username: 'object-id-123',
        credentials_provider: { provider: 'azure', resource: 'https://redis.azure.com' }
      }

      described_class.parse_credentials_provider(config)

      expect(config[:password]).to be_a(Gitlab::Redis::TokenCredential)
      expect(config).not_to have_key(:credentials_provider)
      expect(config[:credentials_provider_descriptor]).to eq(
        provider: 'azure', resource: 'https://redis.azure.com', username: 'object-id-123'
      )
    end

    it 'accepts a String provider name and fills in the username' do
      config = { username: 'object-id-9', credentials_provider: 'azure' }

      described_class.parse_credentials_provider(config)

      expect(config[:credentials_provider_descriptor]).to eq(provider: 'azure', username: 'object-id-9')
    end

    it 'returns nil when called directly with a nil config' do
      expect(described_class.parse_credentials_provider(nil)).to be_nil
    end

    it 'leaves the config untouched when no credentials_provider is set' do
      config = { url: 'redis://cache.example.com' }

      described_class.parse_credentials_provider(config)

      expect(config).not_to have_key(:password)
      expect(config).not_to have_key(:credentials_provider_descriptor)
    end

    it 'produces a marshallable descriptor and password so Sidekiq can serialize the config' do
      config = { username: 'object-id-123', credentials_provider: { provider: 'azure' } }

      described_class.parse_credentials_provider(config)

      expect { Marshal.dump(config[:credentials_provider_descriptor]) }.not_to raise_error
      expect(Marshal.load(Marshal.dump(config[:password]))).to be_a(Gitlab::Redis::TokenCredential)
    end

    it 'raises a clear error when TokenCredential is unavailable (for example under mail_room)' do
      config = { username: 'object-id-123', credentials_provider: { provider: 'azure' } }
      allow(Gitlab::Redis::TokenCredential).to receive(:new).and_raise(NameError)

      expect { described_class.parse_credentials_provider(config) }
        .to raise_error(described_class::CredentialsProviderError, /not supported in this context/)
    end

    it 'raises when combined with Sentinel, which does not validate managed Redis tokens' do
      config = {
        username: 'object-id-123',
        credentials_provider: { provider: 'azure' },
        sentinels: [{ host: 'sentinel1', port: 26379 }]
      }

      expect { described_class.parse_credentials_provider(config) }
        .to raise_error(described_class::CredentialsProviderError, /not supported with Redis Sentinel or Cluster/)
    end

    it 'raises when combined with Cluster, which does not validate managed Redis tokens' do
      config = {
        username: 'object-id-123',
        credentials_provider: { provider: 'azure' },
        cluster: [{ host: 'node1', port: 6379 }]
      }

      expect { described_class.parse_credentials_provider(config) }
        .to raise_error(described_class::CredentialsProviderError, /not supported with Redis Sentinel or Cluster/)
    end
  end
end
