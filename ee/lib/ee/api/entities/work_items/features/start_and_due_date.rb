# frozen_string_literal: true

module EE
  module API
    module Entities
      module WorkItems
        module Features
          module StartAndDueDate
            extend ActiveSupport::Concern

            prepended do
              expose :is_fixed, documentation: { type: 'Boolean', example: true } do |feature, _|
                feature.fixed?
              end

              expose :start_date_sourcing_work_item,
                using: ::API::Entities::WorkItems::Features::WorkItemReference,
                documentation: { type: 'Entities::WorkItems::Features::WorkItemReference' },
                expose_nil: true do |widget, options|
                readable_sourcing_record(widget.start_date_sourcing_work_item, :read_work_item, options)
              end

              expose :start_date_sourcing_milestone,
                using: ::API::Entities::Milestone,
                documentation: { type: 'Entities::Milestone' },
                expose_nil: true do |widget, options|
                readable_sourcing_record(widget.start_date_sourcing_milestone, :read_milestone, options)
              end

              expose :due_date_sourcing_work_item,
                using: ::API::Entities::WorkItems::Features::WorkItemReference,
                documentation: { type: 'Entities::WorkItems::Features::WorkItemReference' },
                expose_nil: true do |widget, options|
                readable_sourcing_record(widget.due_date_sourcing_work_item, :read_work_item, options)
              end

              expose :due_date_sourcing_milestone,
                using: ::API::Entities::Milestone,
                documentation: { type: 'Entities::Milestone' },
                expose_nil: true do |widget, options|
                readable_sourcing_record(widget.due_date_sourcing_milestone, :read_milestone, options)
              end
            end

            private

            def readable_sourcing_record(record, ability, options)
              record if record && Ability.allowed?(options[:current_user], ability, record)
            end
          end
        end
      end
    end
  end
end
