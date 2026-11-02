# frozen_string_literal: true

module API
  module Entities
    module WorkItems
      class Status < Grape::Entity
        expose :id,
          documentation: { type: 'Integer', desc: 'ID of the status.', example: 1 },
          expose_nil: true
        expose :name,
          documentation: { type: 'String', desc: 'Name of the status.', example: 'To do' },
          expose_nil: true
        expose :icon_name,
          documentation: { type: 'String', desc: 'Icon name of the status.', example: 'status-waiting' },
          expose_nil: true
        expose :color,
          documentation: { type: 'String', desc: 'Color of the status.', example: '#737278' },
          expose_nil: true
        expose :position,
          documentation: { type: 'Integer', desc: 'Position of the status within its category.', example: 0 },
          expose_nil: true
        expose :description,
          documentation: { type: 'String', desc: 'Description of the status.' },
          expose_nil: true
        expose :category,
          documentation: { type: 'String', desc: 'Category of the status.', example: 'to_do' },
          expose_nil: true do |status|
          status.category&.to_s
        end
      end
    end
  end
end
