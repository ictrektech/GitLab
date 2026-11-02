# frozen_string_literal: true

require 'omniauth'
require 'securerandom'
require 'digest'

module OmniAuth
  module Strategies
    class Vos
      include OmniAuth::Strategy

      STATE_KEY = 'omniauth.vos'.freeze
      option :name, 'vos'
      option :client_id, 'com.ictrek.gitlab'
      option :endpoint, nil

      uid { @identity.fetch(:uid) }
      info { @identity.slice(:name, :nickname, :email) }

      def request_phase
        session[STATE_KEY] = { 'state' => SecureRandom.hex(32), 'created_at' => Time.now.to_i }
        redirect "#{script_name}/-/vos/sign_in"
      end

      def callback_phase
        return fail!(:invalid_request) unless request.post?
        return fail!(:csrf_detected) unless Gitlab::RequestForgeryProtection.verified?(env)

        pending = session.delete(STATE_KEY)
        state = request.POST['state']
        unless pending.is_a?(Hash) && state.is_a?(String) &&
            pending['created_at'].is_a?(Integer) && (Time.now.to_i - pending['created_at']).between?(0, 300) &&
            ActiveSupport::SecurityUtils.secure_compare(pending['state'].to_s, state)
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
