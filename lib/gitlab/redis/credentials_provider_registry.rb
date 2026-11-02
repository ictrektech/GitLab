# frozen_string_literal: true

module Gitlab
  module Redis
    # Process-global registry of Redis credentials providers, keyed by a
    # marshallable descriptor (a Hash of simple values). Providers are memoized
    # so every pooled connection and thread shares a single provider, which
    # caches the access token and refreshes it as needed.
    #
    # The indirection through a descriptor is deliberate: the descriptor (not
    # the live provider) is what gets embedded in the Redis config, so the
    # config stays marshallable when Sidekiq round-trips it through
    # Marshal.dump/load. The provider itself (which holds tokens and does I/O)
    # is resolved here at runtime and never serialized.
    module CredentialsProviderRegistry
      MUTEX = Mutex.new

      @providers = {}

      class << self
        # Returns the memoized provider for +descriptor+, building it on first
        # use. A provider must respond to `#call` (returning [username, password])
        # and `#expires_at` (a Time, or nil when no token has been fetched yet);
        # the re-auth middleware relies on the expiry to know when to refresh.
        #
        # The middleware calls this on every Redis command on a token-authed
        # connection, so the common cache-hit path is lock-free; only the
        # first build per descriptor takes the mutex.
        def fetch(descriptor)
          @providers[descriptor] || MUTEX.synchronize { @providers[descriptor] ||= build(descriptor) }
        end

        # Injects a provider for a descriptor. Intended for tests.
        def store(descriptor, provider)
          MUTEX.synchronize { @providers[descriptor] = provider }
        end

        def clear!
          MUTEX.synchronize { @providers = {} }
        end

        private

        def build(descriptor)
          case descriptor[:provider].to_s
          when 'azure'
            # Loaded lazily (the gem is `require: false` in the Gemfile) so the
            # dependency is only pulled in when an Azure provider is built.
            require 'az_identity'

            AzIdentity::RedisCredentialsProvider.new(
              username: descriptor[:username],
              resource: descriptor[:resource],
              environment: descriptor[:environment]
            )
          else
            raise ArgumentError, "unknown Redis credentials provider: #{descriptor[:provider].inspect}"
          end
        end
      end
    end
  end
end
