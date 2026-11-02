# frozen_string_literal: true

require 'fast_spec_helper'
require 'redis-client'

RSpec.describe Gitlab::Redis::TokenCredential, feature_category: :redis do
  let(:descriptor) { { provider: 'azure', username: 'oid' } }

  after do
    Gitlab::Redis::CredentialsProviderRegistry.clear!
  end

  describe '#call' do
    it 'returns the current token from the resolved provider' do
      provider = Class.new do
        def call
          %w[oid the-token]
        end
      end.new
      Gitlab::Redis::CredentialsProviderRegistry.store(descriptor, provider)

      expect(described_class.new(descriptor).call('oid')).to eq('the-token')
    end

    it 'raises RedisClient::CannotConnectError when the provider fails to fetch a token' do
      provider = Class.new do
        def call
          raise 'IMDS unavailable'
        end
      end.new
      Gitlab::Redis::CredentialsProviderRegistry.store(descriptor, provider)

      expect { described_class.new(descriptor).call('oid') }
        .to raise_error(RedisClient::CannotConnectError, /failed to acquire Redis token: IMDS unavailable/)
    end
  end

  it 'is marshallable so Sidekiq can serialize the config it lives in' do
    credential = described_class.new(descriptor)

    expect { Marshal.dump(credential) }.not_to raise_error
    expect(Marshal.load(Marshal.dump(credential))).to be_a(described_class)
  end
end
