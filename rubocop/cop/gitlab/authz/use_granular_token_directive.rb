# frozen_string_literal: true

module RuboCop
  module Cop
    module Gitlab
      module Authz
        # Flags `Authz::Tokens::AuthorizeGranularScopesService` in GraphQL code.
        #
        # The GraphQL permissions docs and `gitlab:permissions:validate` read only
        # `authorize_granular_token` directives, so a granular token check made in a
        # resolver is invisible to them. Declare the requirement on the type,
        # mutation or resolver instead.
        #
        # @example
        #   # bad
        #   def resolve(project_path:)
        #     ::Authz::Tokens::AuthorizeGranularScopesService.new(
        #       boundaries: [::Authz::Boundary.for(project)],
        #       permissions: :update_issue,
        #       token: context[:access_token]
        #     ).execute
        #   end
        #
        #   # good
        #   authorize_granular_token permissions: :update_issue,
        #     boundary_argument: :project_path,
        #     boundary_type: :project
        class UseGranularTokenDirective < RuboCop::Cop::Base
          MSG = 'Do not check granular token permissions with `Authz::Tokens::AuthorizeGranularScopesService` ' \
            'in GraphQL code. Declare them with `authorize_granular_token`, so the docs and ' \
            '`gitlab:permissions:validate` see them. See https://docs.gitlab.com/development/permissions/' \
            'granular_access/graphql_implementation_guide/#step-5-add-authorization-directives-to-types-and-mutations'

          # @!method granular_scopes_service?(node)
          def_node_matcher :granular_scopes_service?, <<~PATTERN
            (const (const (const {nil? cbase} :Authz) :Tokens) :AuthorizeGranularScopesService)
          PATTERN

          def on_const(node)
            add_offense(node) if granular_scopes_service?(node)
          end
        end
      end
    end
  end
end
