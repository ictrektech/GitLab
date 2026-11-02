# frozen_string_literal: true

module EE
  module Gitlab
    module Auth
      module RequestAuthenticator
        extend ::Gitlab::Utils::Override

        private

        override :find_user_for_graphql_api_request
        def find_user_for_graphql_api_request
          find_user_from_geo_token || super
        end

        override :graphql_authorization_scopes
        def graphql_authorization_scopes
          super + [:ai_features, :ai_workflows]
        end

        # The rate limiters identify the requester before the endpoint authenticates it, and the endpoint already
        # streams this event, so auditing here too would send it once per lookup instead of once per request.
        override :audit_job_token_authentication
        def audit_job_token_authentication(_user); end
      end
    end
  end
end
