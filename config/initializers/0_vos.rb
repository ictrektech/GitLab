# frozen_string_literal: true

require_dependency 'omni_auth/strategies/vos'

module Gitlab
  module Auth
    module Vos
      module RateLimits
        def rule_definitions
          super.merge(
            vos_authentication_ip: ::Labkit::RateLimit::Rule.new(
              name: 'limit_vos_authentication_by_ip', characteristics: %i[ip],
              limit: 30, period: 60, action: :limit),
            vos_authentication_token: ::Labkit::RateLimit::Rule.new(
              name: 'limit_vos_authentication_by_token', characteristics: %i[user],
              limit: 10, period: 60, action: :limit),
            vos_authentication_user: ::Labkit::RateLimit::Rule.new(
              name: 'limit_vos_authentication_by_subject', characteristics: %i[user],
              limit: 10, period: 60, action: :limit)
          )
        end
      end
    end
  end
end

Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.singleton_class.prepend(Gitlab::Auth::Vos::RateLimits)

Rails.application.routes.prepend do
  get '/-/vos/sign_in', to: 'vos/sessions#new', as: :vos_sign_in
  get '/-/vos/fastpath.js', to: 'vos/sessions#script', as: :vos_fastpath
end

Rails.application.config.to_prepare do
  OmniauthCallbacksController.prepend(Gitlab::Auth::Vos::Callbacks)
end
