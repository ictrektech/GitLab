# frozen_string_literal: true

require 'omniauth'
require 'securerandom'
require 'digest'

module OmniAuth
  module Strategies
    class Vos
      include OmniAuth::Strategy

      CHALLENGE_PREFIX = 'vos:oauth:challenge'.freeze
      CONSUME_CHALLENGE = <<~LUA.freeze
        if redis.call('get', KEYS[1]) == ARGV[1] then
          return redis.call('getdel', KEYS[1])
        end
      LUA
      option :name, 'vos'
      option :client_id, 'com.ictrek.gitlab'
      option :endpoint, nil

      uid { @identity.fetch(:uid) }
      info { @identity.slice(:name, :nickname, :email) }

      def self.pending_challenge(state, session, consume: false)
        return unless state.is_a?(String) && state.match?(/\A[0-9a-f]{64}\z/)
        return unless session['_csrf_token'].present?

        expected = Digest::SHA256.hexdigest(session['_csrf_token'])
        stored = Gitlab::Redis::SharedState.with do |redis|
          key = "#{CHALLENGE_PREFIX}:#{state}"
          consume ? redis.eval(CONSUME_CHALLENGE, keys: [key], argv: [expected]) : redis.get(key)
        end
        return unless stored && ActiveSupport::SecurityUtils.secure_compare(stored, expected)

        { 'state' => state }
      end

      def request_phase
        return fail!(:csrf_detected) unless session['_csrf_token'].present?

        state = SecureRandom.hex(32)
        binding = Digest::SHA256.hexdigest(session['_csrf_token'])
        Gitlab::Redis::SharedState.with do |redis|
          redis.set("#{CHALLENGE_PREFIX}:#{state}", binding, ex: 300)
        end
        redirect "#{script_name}/-/vos/sign_in?state=#{state}"
      end

      def callback_phase
        return fail!(:invalid_request) unless request.post?
        unless Gitlab::RequestForgeryProtection.verified?(env)
          Gitlab::AppLogger.warn(event: 'vos_authentication', stage: 'csrf_rejected')
          return fail!(:csrf_detected)
        end

        state = request.POST['state']
        unless self.class.pending_challenge(state, session, consume: true)
          Gitlab::AppLogger.warn(event: 'vos_authentication', stage: 'state_rejected')
          return fail!(:csrf_detected)
        end

        token = request.POST['access_token']
        return fail!(:invalid_credentials) unless token.is_a?(String) && token.bytesize.between?(1, 8192)

        fingerprint = Digest::SHA256.hexdigest(token)
        if Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_ip, scope: { ip: request.ip }) ||
            Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_token, scope: { user: fingerprint })
          return fail!(:rate_limited)
        end

        @identity = Gitlab::Auth::Vos::Client.new(endpoint: options.endpoint, client_id: options.client_id).verify(token)
        if Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_user, scope: { user: @identity.fetch(:uid) })
          return fail!(:rate_limited)
        end
        super
      rescue Gitlab::Auth::Vos::Client::InvalidIdentity
        fail!(:invalid_credentials)
      end
    end
  end
end
