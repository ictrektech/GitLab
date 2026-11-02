# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class CreateCompositeOauthAccessTokenService
      include ::Services::ReturnServiceResponses
      include ::Gitlab::Utils::StrongMemoize

      CompositeIdentityEnforcedError = Class.new(StandardError)
      IncompleteOnboardingError = Class.new(StandardError)
      TOKEN_EXPIRES_IN = 1.hour

      def initialize(current_user:, organization:, service_account:, scopes: nil, container: nil)
        @current_user = current_user
        @organization = organization
        @service_account = service_account
        @container = container
        @scopes = scopes || (::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE])
        @scopes += dynamic_user_scope unless use_jwt_issuer?
      end

      def execute
        ensure_service_account!

        token =
          if use_jwt_issuer?
            create_jwt_token
          else
            ensure_oauth_application!
            create_oauth_access_token
          end

        return ServiceResponse.error(message: "Failed to generate composite oauth token") unless token

        stick_to_database_load_balancer(token) unless use_jwt_issuer?

        audit_token_creation(token)
        success(oauth_access_token: token)
      end

      private

      # Memoized: @scopes (set in #initialize) and #execute must agree on one answer.
      def use_jwt_issuer?
        ::Gitlab::Auth::StatelessAccessTokenGate.issuance_enabled?(@current_user)
      end
      strong_memoize_attr :use_jwt_issuer?

      # sub = service account (composite identity primary); the human user is
      # carried in gitlab.identities rather than a `user:<id>` Doorkeeper scope.
      def create_jwt_token
        ::Authn::Tokens::StatelessAccessToken.issue(
          user: @service_account,
          organization: @organization,
          ttl: TOKEN_EXPIRES_IN.to_i,
          scopes: @scopes,
          identities: [{ kind: ::Authn::Tokens::StatelessAccessToken::IDENTITY_KIND_USER, local_id: @current_user.id }],
          routing: { o: @organization.id, u: @current_user.id }
        )
      end

      def audit_token_creation(token)
        audit_context = {
          name: 'composite_oauth_token_created',
          author: @current_user,
          scope: @container || @service_account,
          target: @service_account,
          target_details: @service_account.name,
          message: 'Created composite OAuth token for Duo workflow',
          additional_details: {
            scopes: token.scopes.to_a,
            expires_in: TOKEN_EXPIRES_IN.to_i,
            token_type: use_jwt_issuer? ? 'stateless_jwt' : 'oauth'
          }
        }

        ::Gitlab::Audit::Auditor.audit(audit_context)
      end

      def create_oauth_access_token
        return unless ai_settings.duo_workflow_oauth_application_id

        OauthAccessToken.create!(
          application_id: ai_settings.duo_workflow_oauth_application_id,
          expires_in: TOKEN_EXPIRES_IN,
          resource_owner_id: @service_account.id,
          organization: @organization,
          scopes: @scopes
        )
      end

      # A token created on the primary may not have reached a replica by the time the workload
      # authenticates with it. Sticking keeps those reads on the primary until replicas catch up,
      # otherwise the token lookup misses and the request is rejected with a 401.
      def stick_to_database_load_balancer(token)
        ::OauthAccessToken.sticking.stick(:oauth_token, token.plaintext_token, hash_id: true)
      end

      def ensure_service_account!
        return unless @service_account.nil? || !@service_account.composite_identity_enforced?

        raise CompositeIdentityEnforcedError,
          'Service account does not exist or does not have composite identity enabled.'
      end

      def ensure_oauth_application!
        return if oauth_application&.scopes&.include?(::Gitlab::Auth::MCP_SCOPE.to_s)

        scopes = ::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE, ::Gitlab::Auth::DYNAMIC_USER]

        # Add missing scope if the application exists
        if oauth_application.present?
          oauth_application.update!(scopes: scopes)

          return
        end

        ApplicationRecord.transaction do
          oauth_app = Authn::OauthApplication.create!(
            name: 'GitLab Duo Agent Platform Composite OAuth Application',
            redirect_uri: oauth_callback_url,
            scopes: scopes,
            trusted: true,
            confidential: true,
            organization: @organization
          )
          ai_settings.update!(duo_workflow_oauth_application_id: oauth_app.id)
        end
      rescue ActiveRecord::RecordInvalid => e
        Gitlab::AppLogger.error("Failed to create OAuth application: #{e.message}")
      end

      def oauth_callback_url
        Gitlab::Routing.url_helpers.root_url
      end

      def oauth_application
        ai_settings.duo_workflow_oauth_application
      end

      def dynamic_user_scope
        ["user:#{@current_user.id}"]
      end

      def ai_settings
        Ai::Setting.for_organization(@organization)
      end
      strong_memoize_attr :ai_settings
    end
  end
end
