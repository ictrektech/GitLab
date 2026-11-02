# frozen_string_literal: true

module Gitlab
  module Graphql
    module Ai
      module DuoWorkflows
        # Same as FieldCallCount, but only enforced while the derisk flag is enabled.
        class LinkFieldCallCount < ::Gitlab::Graphql::Limit::FieldCallCount
          def resolve(object:, arguments:, context:)
            unless Feature.enabled?(:limit_duo_workflow_link_fields, context[:current_user], type: :gitlab_com_derisk)
              return yield(object, arguments)
            end

            super
          end
        end
      end
    end
  end
end
