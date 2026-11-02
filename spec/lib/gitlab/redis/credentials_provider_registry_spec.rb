# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Redis::CredentialsProviderRegistry, feature_category: :redis do
  after do
    described_class.clear!
  end

  describe '.fetch' do
    # The az_identity gem is `require: false`; stub the lazy require so specs do
    # not depend on the real gem being loadable.
    before do
      allow(described_class).to receive(:require).with('az_identity')
    end

    it 'memoizes the provider for a descriptor' do
      provider = Object.new
      allow(described_class).to receive(:build).and_return(provider)

      descriptor = { provider: 'azure', username: 'oid' }

      expect(described_class.fetch(descriptor)).to be(provider)
      expect(described_class.fetch(descriptor)).to be(provider)
      expect(described_class).to have_received(:build).once
    end

    it 'raises for an unknown provider' do
      expect { described_class.fetch(provider: 'nope') }
        .to raise_error(ArgumentError, /unknown Redis credentials provider/)
    end

    it 'builds an Azure provider from the descriptor' do
      azure_class = Class.new
      built = Object.new
      stub_const('AzIdentity::RedisCredentialsProvider', azure_class)
      allow(azure_class).to receive(:new).and_return(built)

      descriptor = { provider: 'azure', username: 'oid', resource: 'https://redis.azure.com', environment: 'AzureCloud' }

      expect(described_class.fetch(descriptor)).to be(built)
      expect(azure_class).to have_received(:new).with(
        username: 'oid', resource: 'https://redis.azure.com', environment: 'AzureCloud'
      )
    end

    it 'loads the az_identity gem lazily only when building an Azure provider' do
      stub_const('AzIdentity::RedisCredentialsProvider', Class.new)
      allow(AzIdentity::RedisCredentialsProvider).to receive(:new).and_return(Object.new)

      expect(described_class).to receive(:require).with('az_identity')

      described_class.fetch(provider: 'azure', username: 'oid')
    end

    it 'does not load the az_identity gem for an unknown provider' do
      expect(described_class).not_to receive(:require)

      expect { described_class.fetch(provider: 'nope') }
        .to raise_error(ArgumentError, /unknown Redis credentials provider/)
    end
  end

  describe '.store' do
    it 'injects a provider for a descriptor' do
      provider = Object.new
      descriptor = { provider: 'azure' }

      described_class.store(descriptor, provider)

      expect(described_class.fetch(descriptor)).to be(provider)
    end
  end
end
