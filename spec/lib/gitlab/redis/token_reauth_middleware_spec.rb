# frozen_string_literal: true

require 'fast_spec_helper'
require 'active_support/all'
require 'labkit/fields'
require 'redis-client'

RSpec.describe Gitlab::Redis::TokenReauthMiddleware, feature_category: :redis do
  # Mimic how redis-client mixes the middleware into its Middlewares class: the
  # module overrides #call/#call_pipelined and delegates to a base via super.
  let(:base_class) do
    Class.new do
      attr_reader :client

      def initialize(client)
        @client = client
      end

      def call(_command, _config)
        :command_result
      end

      def call_pipelined(_commands, _config)
        :pipelined_result
      end
    end
  end

  let(:middleware_class) do
    Class.new(base_class).tap { |klass| klass.include(described_class) }
  end

  # Records AUTH commands issued by the middleware.
  let(:client) do
    Class.new do
      def calls
        @calls ||= []
      end

      def call(*args)
        calls << args
        :auth_ok
      end
    end.new
  end

  let(:middleware) { middleware_class.new(client) }
  let(:descriptor) { { provider: 'azure', username: 'oid' } }
  let(:config) { config_struct.new(custom: { credentials_provider: descriptor }, username: 'oid') }
  let(:config_struct) { Struct.new(:custom, :username, keyword_init: true) }

  after do
    Gitlab::Redis::CredentialsProviderRegistry.clear!
  end

  def stub_provider(expires_at:, token: 'fresh-token')
    provider = Struct.new(:expires_at, :token, keyword_init: true) do
      def call
        ['oid', token]
      end
    end.new(expires_at: expires_at, token: token)

    Gitlab::Redis::CredentialsProviderRegistry.store(descriptor, provider)
    provider
  end

  context 'when no credentials provider is configured' do
    let(:config) { config_struct.new(custom: {}, username: 'default') }

    it 'does not re-authenticate and forwards the command' do
      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end

    it 'does not track expiry for an AUTH prelude on a non-provider connection' do
      expect(middleware.call_pipelined([%w[AUTH default pw]], config)).to eq(:pipelined_result)
      expect(client.calls).to be_empty
    end
  end

  context 'when the token is not near expiry' do
    it 'does not re-authenticate' do
      stub_provider(expires_at: 1.hour.from_now)

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end
  end

  context 'when the provider does not expose an expiry' do
    it 'does not re-authenticate on every command' do
      stub_provider(expires_at: nil)

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end
  end

  context 'when the token is within the re-auth leeway' do
    it 'issues AUTH with the configured username and a fresh token before the command' do
      stub_provider(expires_at: 1.second.ago, token: 'rotated-token')

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to include(%w[AUTH oid rotated-token])
    end

    it 'also re-authenticates before a pipelined call' do
      stub_provider(expires_at: 1.second.ago, token: 'rotated-token')

      expect(middleware.call_pipelined([%w[GET foo]], config)).to eq(:pipelined_result)
      expect(client.calls).to include(%w[AUTH oid rotated-token])
    end

    it 'does not re-authenticate before an AUTH command, to avoid recursion' do
      stub_provider(expires_at: 1.second.ago, token: 'rotated-token')

      expect(middleware.call(%w[AUTH oid rotated-token], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end

    it 'does not issue AUTH when the provider returns no token' do
      stub_provider(expires_at: 1.second.ago, token: nil)

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end
  end

  context 'when a connection authed before another connection advanced the shared expiry' do
    it 're-auths based on this connection token expiry, not the shared provider expiry' do
      provider = stub_provider(expires_at: 1.second.ago, token: 'old-token')

      # This connection's prelude authenticates with the current (near-expiry)
      # token; the middleware records that token's expiry for the connection.
      middleware.call_pipelined([%w[AUTH oid old-token], %w[SELECT 0]], config)
      expect(client.calls).to be_empty

      # A different connection triggers a refresh: the shared provider now
      # reports a far-future expiry and hands out a rotated token.
      provider.expires_at = 1.hour.from_now
      provider.token = 'rotated-token'

      # This connection still holds the old token, so it must re-auth even
      # though the shared provider expiry is now in the future.
      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to include(%w[AUTH oid rotated-token])
    end

    it 'does not re-auth a connection that already authed with the rotated token' do
      stub_provider(expires_at: 1.hour.from_now, token: 'rotated-token')

      middleware.call_pipelined([%w[AUTH oid rotated-token]], config)
      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
    end

    it 'tracks expiry from a RESP3 HELLO AUTH prelude' do
      provider = stub_provider(expires_at: 1.second.ago, token: 'old-token')

      # RESP3 connections (Sidekiq 7) authenticate in the prelude as
      # `HELLO 3 AUTH <user> <token>` rather than a bare AUTH.
      middleware.call_pipelined([%w[HELLO 3 AUTH oid old-token]], config)
      expect(client.calls).to be_empty

      provider.expires_at = 1.hour.from_now
      provider.token = 'rotated-token'

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to include(%w[AUTH oid rotated-token])
    end
  end

  context 'when refreshing the token fails within the leeway' do
    let(:failing_provider) do
      Struct.new(:expires_at) do
        def call
          raise 'IMDS unavailable'
        end
      end.new(1.second.ago)
    end

    before do
      Gitlab::Redis::CredentialsProviderRegistry.store(descriptor, failing_provider)
    end

    it 'logs and lets the command proceed on the existing credentials' do
      allow(Gitlab::AppLogger).to receive(:warn)

      expect(middleware.call(%w[GET foo], config)).to eq(:command_result)
      expect(client.calls).to be_empty
      expect(Gitlab::AppLogger).to have_received(:warn)
        .with(hash_including(
          message: 'Redis token re-authentication failed',
          Labkit::Fields::ERROR_MESSAGE => 'IMDS unavailable'
        ))
    end

    it 'throttles the warning to avoid flooding logs on sustained failures' do
      allow(Gitlab::AppLogger).to receive(:warn)

      5.times { middleware.call(%w[GET foo], config) }

      expect(Gitlab::AppLogger).to have_received(:warn).once
    end
  end

  context 'when mixed into the real redis-client middleware base' do
    # Proves `client` comes from RedisClient::BasicMiddleware (what the gem
    # actually mixes this module into via `config.middlewares_stack.new(self)`),
    # not just from the spec's hand-rolled base_class. Guards against the
    # middleware silently no-op'ing in production if that accessor were absent.
    let(:real_middleware) do
      Class.new(RedisClient::BasicMiddleware) { include Gitlab::Redis::TokenReauthMiddleware }.new(client)
    end

    it 'exposes the client accessor the gem provides' do
      expect(RedisClient::BasicMiddleware.method_defined?(:client)).to be(true)
      expect(real_middleware.client).to be(client)
    end

    it 'issues AUTH through client and yields the command, as redis-client invokes it' do
      stub_provider(expires_at: 1.second.ago, token: 'rotated-token')

      result = real_middleware.call(%w[GET foo], config) { |cmd| [:sent, cmd] }

      expect(client.calls).to include(%w[AUTH oid rotated-token])
      expect(result).to eq([:sent, %w[GET foo]])
    end
  end
end
