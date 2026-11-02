# frozen_string_literal: true

module Types
  module Ai
    module Catalog
      class GroupItemEnabledByEnum < BaseEnum
        graphql_name 'AiCatalogGroupItemEnabledBy'
        description 'Ways an AI Catalog item can be enabled in a group.'

        value 'INHERITANCE',
          value: 'inheritance',
          description: 'Enabled for all projects in the group through group inheritance. ' \
            'Only top-level groups can enable items this way. ' \
            'Matches no items unless the `ai_catalog_group_inherited_consumers` feature flag is enabled.'

        value 'PROJECT_DIRECT',
          value: 'project_direct',
          description: 'Enabled directly in any descendant project in the group.'
      end
    end
  end
end
