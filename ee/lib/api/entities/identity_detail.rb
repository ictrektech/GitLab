# frozen_string_literal: true

module API
  module Entities
    class IdentityDetail < Grape::Entity
      expose :extern_uid, documentation: { type: 'String' }
      expose :user_id, documentation: { type: 'Integer' }
      expose :active, documentation: { type: 'Boolean' }, if: ->(identity) { identity.has_attribute?(:active) }
    end
  end
end
