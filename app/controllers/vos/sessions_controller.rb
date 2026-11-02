# frozen_string_literal: true

module Vos
  class SessionsController < ApplicationController
    feature_category :system_access
    skip_before_action :authenticate_user!, :require_email, :active_user_check, :check_password_expiration,
      :enforce_terms!, :ldap_security_check, :check_two_factor_requirement, raise: false
    # This action serves only public, static JavaScript without session data.
    skip_forgery_protection only: %i[script locale_script]
    before_action :require_vos_provider

    def new
      response.headers['Cache-Control'] = 'no-store'
      @pending = OmniAuth::Strategies::Vos.pending_challenge(params[:state], session)
      return redirect_to(vos_app_path) if params[:state].blank? && params[:embedded].blank?
      @client_id = Gitlab::Auth::OAuth::Provider.config_for('vos').dig('args', 'client_id') || 'com.ictrek.gitlab'
      render layout: 'devise_empty'
    end

    def app
      response.headers['Cache-Control'] = 'no-store'
      render layout: false
    end

    def locale_script
      response.headers['Cache-Control'] = 'no-store'
      render file: Rails.root.join('lib/gitlab/auth/vos/locale.js'),
        content_type: 'application/javascript', layout: false
    end

    def style
      render file: Rails.root.join('lib/gitlab/auth/vos/shell.css'), content_type: 'text/css', layout: false
    end

    def script
      response.headers['Cache-Control'] = 'no-store'
      render file: Rails.root.join('lib/gitlab/auth/vos/fastpath.js'),
        content_type: 'application/javascript', layout: false
    end

    private

    def require_vos_provider
      render_404 unless Gitlab::Auth::OAuth::Provider.sign_in_enabled?('vos')
    end
  end
end
