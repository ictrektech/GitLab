# frozen_string_literal: true

module API
  module Entities
    class SamlGroupLink < Grape::Entity
      expose :saml_group_name, as: :name, documentation: { type: 'String', example: 'saml-group-1' }
      # rubocop:disable API/AccessLevelStringType -- Introduced before the cop
      expose :access_level, documentation: { type: 'Integer', example: 40 }
      # rubocop:enable API/AccessLevelStringType
      expose :member_role_id,
        documentation: { type: 'Integer', format: 'int64', example: 12 }, if: ->(instance, _options) do
          instance.group.custom_roles_enabled?
        end
      expose :provider, documentation: { type: 'String', example: 'saml' }
    end
  end
end
