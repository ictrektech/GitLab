# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module SessionCredits
      # Per-source pause for the v2 sessions sync. The source is the root namespace id, or
      # `instance` on self-managed. Only CustomersDot's explicit signals set it; a pause never
      # spreads to another source, and nothing escalates. A lost key is the safe failure mode,
      # so Redis errors are swallowed.
      module SyncPause
        # Hash-tagged so the keys share a slot on Redis Cluster.
        KEY_PREFIX = 'duo_workflow_session_credits_v2:{pause}'

        def self.pause!(source:, reason:, duration:)
          with_redis { |redis| redis.set(key(source), reason.to_s, ex: duration.to_i) }
        end

        def self.reason(source:)
          with_redis { |redis| redis.get(key(source)) }&.to_sym
        end

        # Console override when CustomersDot is known healthy again.
        def self.clear!(source:)
          with_redis { |redis| redis.del(key(source)) }
        end

        def self.key(source)
          "#{KEY_PREFIX}:#{source}"
        end

        def self.with_redis(&block)
          ::Gitlab::Redis::SharedState.with(&block) # rubocop:disable CodeReuse/ActiveRecord -- redis pool, not active record
        rescue ::Redis::BaseError, ::RedisClient::Error => e
          ::Gitlab::ErrorTracking.track_exception(e)
          nil
        end
        private_class_method :with_redis
      end
    end
  end
end
