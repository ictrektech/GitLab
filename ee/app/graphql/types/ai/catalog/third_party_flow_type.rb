# frozen_string_literal: true

module Types
  module Ai
    module Catalog
      class ThirdPartyFlowType < ::Types::BaseObject
        graphql_name 'AiCatalogThirdPartyFlow'
        description 'An AI catalog third party flow'
        authorize :read_ai_catalog_item
        authorize_granular_token permissions: :read_ai_catalog_item, boundary: :user, boundary_type: :user

        implements ::Types::Ai::Catalog::ItemInterface

        field :accepts_trigger_goal, GraphQL::Types::Boolean,
          null: false,
          method: :accepts_trigger_goal?,
          experiment: { milestone: '19.5' },
          description: 'Whether a flow trigger for the flow can carry a configured goal.'
      end
    end
  end
end
