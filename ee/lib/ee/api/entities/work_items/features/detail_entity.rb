# frozen_string_literal: true

module EE
  module API
    module Entities
      module WorkItems
        module Features
          module DetailEntity
            extend ActiveSupport::Concern

            prepended do
              expose_feature :color,
                using: ::API::Entities::WorkItems::Features::Color,
                documentation: { type: 'Entities::WorkItems::Features::Color' },
                expose_nil: true

              expose_feature :progress,
                using: ::API::Entities::WorkItems::Features::Progress,
                documentation: { type: 'Entities::WorkItems::Features::Progress' },
                expose_nil: true

              expose_feature :iteration,
                using: ::API::Entities::WorkItems::Features::Iteration,
                documentation: { type: 'Entities::WorkItems::Features::Iteration' },
                expose_nil: true

              expose_feature :health_status,
                using: ::API::Entities::WorkItems::Features::HealthStatusDetail,
                documentation: { type: 'Entities::WorkItems::Features::HealthStatusDetail' },
                expose_nil: true

              expose_feature :weight,
                using: ::API::Entities::WorkItems::Features::Weight,
                documentation: { type: 'Entities::WorkItems::Features::Weight' },
                expose_nil: true

              expose_feature :requirement_legacy,
                using: ::API::Entities::WorkItems::Features::RequirementLegacy,
                documentation: { type: 'Entities::WorkItems::Features::RequirementLegacy' },
                expose_nil: true

              expose_feature :status,
                using: ::API::Entities::WorkItems::Features::Status,
                documentation: { type: 'Entities::WorkItems::Features::Status' },
                expose_nil: true

              expose_feature :verification_status,
                using: ::API::Entities::WorkItems::Features::VerificationStatus,
                documentation: { type: 'Entities::WorkItems::Features::VerificationStatus' },
                expose_nil: true

              expose_feature :linked_items,
                using: ::API::Entities::WorkItems::Features::LinkedItems,
                documentation: { type: 'Entities::WorkItems::Features::LinkedItems' },
                expose_nil: true

              expose_feature :custom_fields,
                using: ::API::Entities::WorkItems::Features::CustomFields,
                documentation: { type: 'Entities::WorkItems::Features::CustomFields' },
                expose_nil: true
            end
          end
        end
      end
    end
  end
end
