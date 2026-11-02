# frozen_string_literal: true

module Mcp
  module Tools
    module Concerns
      module GranularTokenAuthorization
        private

        def authorize_granular_token!(resource, permissions, not_found_message:)
          raise ::Mcp::Tools::Concerns::ResourceFinder::ResourceForbiddenError, not_found_message if access_token.nil?

          response = ::Authz::Tokens::AuthorizeGranularScopesService.new(
            boundaries: ::Authz::Boundary.for(resource),
            permissions: permissions,
            token: access_token
          ).execute
          return if response.success?

          if response.reason == :resource_not_found
            raise ::Mcp::Tools::Concerns::ResourceFinder::ResourceNotFoundError, not_found_message
          end

          ::Current.add_granular_denied_permissions(response.payload[:denied_permissions])
          raise ::Mcp::Tools::Concerns::ResourceFinder::ResourceForbiddenError, response.message
        end
      end
    end
  end
end
