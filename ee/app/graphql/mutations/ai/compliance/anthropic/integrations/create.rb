# frozen_string_literal: true

module Mutations
  module Ai
    module Compliance
      module Anthropic
        module Integrations
          class Create < BaseMutation
            graphql_name 'AnthropicComplianceIntegrationCreate'
            description 'Verifies a Compliance Access Key with Anthropic, then stores it as the ' \
              'Anthropic Compliance integration of a top-level group.'

            include Mutations::ResolvesGroup

            authorize :create_anthropic_compliance_integration

            authorize_granular_token permissions: :create_anthropic_compliance_integration,
              boundary_argument: :group_path, boundary_type: :group

            argument :group_path, GraphQL::Types::ID,
              required: true,
              description: 'Full path of the top-level group.'

            argument :api_key, GraphQL::Types::String,
              required: true,
              description: 'Anthropic Compliance Access Key with the `read:compliance_user_data` scope. ' \
                'Write-only: GitLab never returns it.'

            field :anthropic_compliance_integration, ::Types::Ai::Compliance::Anthropic::IntegrationType,
              null: true,
              description: 'Integration after the mutation.'

            field :error_reason, ::Types::Ai::Compliance::Anthropic::IntegrationErrorReasonEnum,
              null: true,
              description: 'Machine-readable reason for the mutation error.'

            def resolve(group_path:, api_key:)
              group = authorized_find!(group_path: group_path)

              return rate_limited_response if rate_limited?(group)

              integration = ::Ai::Compliance::Anthropic::Integration.new(namespace: group)
              result = ::Ai::Compliance::Anthropic::SetAccessKeyService.new(integration, api_key: api_key).execute

              return error_response(result.message, result.reason) if result.error?

              audit(group)

              { anthropic_compliance_integration: integration, errors: [], error_reason: nil }
            end

            private

            def find_object(group_path:)
              resolve_group(full_path: group_path)
            end

            # Every attempt can reach Anthropic, so without a limit GitLab could be used to test
            # stolen keys. The user limit stops one actor spreading attempts across groups.
            def rate_limited?(group)
              ::Gitlab::ApplicationRateLimiter.throttled?(
                :anthropic_compliance_key_verification_by_group, scope: { group: group }
              ) || ::Gitlab::ApplicationRateLimiter.throttled?(
                :anthropic_compliance_key_verification_by_user, scope: { user: current_user }
              )
            end

            def rate_limited_response
              error_response(
                s_('AiGovernance|Too many Compliance Access Key verification attempts. Try again later.'),
                :rate_limited
              )
            end

            def error_response(message, reason)
              { anthropic_compliance_integration: nil, errors: [message], error_reason: reason }
            end

            def audit(group)
              ::Gitlab::Audit::Auditor.audit(
                name: 'anthropic_compliance_integration_created',
                author: current_user,
                scope: group,
                target: group,
                message: 'Created Anthropic Compliance integration'
              )
            end
          end
        end
      end
    end
  end
end
