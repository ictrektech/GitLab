# frozen_string_literal: true

module EE
  module Gitlab
    module Auth
      module AuthFinders
        extend ActiveSupport::Concern
        extend ::Gitlab::Utils::Override

        prepended do
          include ::Gitlab::Auth::RemoteDevelopment::AuthFinders
        end

        def find_user_from_geo_token
          return unless geo_api_request?

          token = current_request.authorization
          return unless ::Gitlab::Geo::JwtRequestDecoder.geo_auth_attempt?(token)

          geo_jwt_decoder = ::Gitlab::Geo::JwtRequestDecoder.new(token)
          raise(::Gitlab::Auth::UnauthorizedError) unless valid_geo_token?(geo_jwt_decoder)

          ::User.find(geo_jwt_decoder.decode[:authenticating_user_id])
        rescue ::ActiveRecord::RecordNotFound
          raise(::Gitlab::Auth::UnauthorizedError)
        end

        def valid_geo_token?(geo_jwt_decoder)
          geo_jwt_decoder.valid_scope?(::Gitlab::Geo::API_SCOPE)
        rescue ::Gitlab::Geo::InvalidDecryptionKeyError, ::Gitlab::Geo::InvalidSignatureTimeError => e
          ::Gitlab::ErrorTracking.track_exception(e)
          false
        end

        override :find_oauth_access_token
        def find_oauth_access_token
          return if scim_request?

          super
        end

        # Feeds the shared `access_token` dispatcher so StatelessAccessToken
        # gets the same validation/logging as PAT/OAuth tokens. Skips
        # endpoints with their own `authenticate_with` allowlist entirely.
        override :resolve_access_token
        def resolve_access_token
          return super if namespace_inheritable_authentication?

          find_stateless_access_token || super
        end

        def scim_request?
          current_request.path.starts_with?("/api/scim/")
        end

        def geo_api_request?
          current_request.path.starts_with?("/api/#{::API::API.version}/geo/")
        end

        override :find_user_from_job_token
        def find_user_from_job_token
          user = super
          return unless user

          audit_job_token_authentication(user)

          user
        end

        def runner_controller_token_from_authorization_token
          return unless route_authentication_setting[:runner_controller_token_allowed]

          self.current_token = current_request.headers[::Gitlab::Kas::INTERNAL_API_AGENT_REQUEST_HEADER]

          return unless current_token.present?

          ::Ci::RunnerControllerToken.active.find_by_token(current_token.to_s)
        end

        private

        def find_stateless_access_token
          return if scim_request?

          # Header-only, unlike parsed_oauth_token: these JWTs are minted
          # automatically at volume, and accepting them as a query parameter
          # would leak them into access/proxy logs and Referer headers.
          token_string = ::Doorkeeper::OAuth::Token.from_bearer_authorization(current_request)
          return unless token_string

          token = ::Authn::Tokens::StatelessAccessToken.from_jwt(token_string)
          return unless token
          return unless ::Gitlab::Auth::StatelessAccessTokenGate.enabled?(token)

          self.current_token = token_string
          ::Gitlab::Auth::Identity.link_from_oauth_token(token).tap do |identity|
            raise ::Gitlab::Auth::UnauthorizedError if identity && !identity.valid?
          end

          token
        end

        def audit_job_token_authentication(user)
          # rubocop:disable Gitlab/ModuleWithInstanceVariables -- Already used in super
          audit_context = {
            name: "user_authenticated_using_job_token",
            author: user,
            scope: @current_authenticated_job.project,
            target: @current_authenticated_job,
            target_details: @current_authenticated_job.id.to_s,
            message: "#{user.name} authenticated using job token of job id: #{@current_authenticated_job.id}"
          }
          # rubocop:enable Gitlab/ModuleWithInstanceVariables

          ::Gitlab::Audit::Auditor.audit(audit_context)
        end
      end
    end
  end
end
