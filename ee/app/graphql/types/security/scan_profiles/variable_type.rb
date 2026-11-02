# frozen_string_literal: true

module Types
  module Security
    module ScanProfiles
      # rubocop:disable Graphql/AuthorizeTypes -- Static data, the same for every user
      class VariableType < BaseObject
        graphql_name 'SecurityScanProfileVariable'
        description 'A configuration variable that a scan profile of a given type can set.'

        authorize_granular_token permissions: :read_metadata, boundary: :instance, boundary_type: :instance

        field :key, GraphQL::Types::String,
          null: false,
          description: 'Name of the configuration field, as used in the scan profile configuration input.'

        field :env_var, GraphQL::Types::String,
          null: true,
          description: 'CI/CD variable the configuration field is passed to the scan as.'
      end
      # rubocop:enable Graphql/AuthorizeTypes
    end
  end
end
