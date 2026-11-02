# frozen_string_literal: true

module EE
  module API
    module Entities
      module WorkItems
        module Features
          module Entity
            extend ActiveSupport::Concern

            prepended do
              expose_feature :color,
                using: ::API::Entities::WorkItems::Features::Color,
                documentation: { type: 'Entities::WorkItems::Features::Color', desc: 'Premium and Ultimate only.' },
                expose_nil: true

              expose_feature :progress,
                using: ::API::Entities::WorkItems::Features::Progress,
                documentation: { type: 'Entities::WorkItems::Features::Progress', desc: 'Ultimate only.' },
                expose_nil: true

              expose_feature :iteration,
                using: ::API::Entities::WorkItems::Features::Iteration,
                documentation: { type: 'Entities::WorkItems::Features::Iteration', desc: 'Premium and Ultimate only.' },
                expose_nil: true

              expose_feature :health_status,
                using: ::API::Entities::WorkItems::Features::HealthStatus,
                documentation: { type: 'Entities::WorkItems::Features::HealthStatus', desc: 'Ultimate only.' },
                expose_nil: true

              expose_feature :weight,
                using: ::API::Entities::WorkItems::Features::Weight,
                documentation: { type: 'Entities::WorkItems::Features::Weight', desc: 'Premium and Ultimate only.' },
                expose_nil: true

              expose_feature :requirement_legacy,
                using: ::API::Entities::WorkItems::Features::RequirementLegacy,
                documentation: { type: 'Entities::WorkItems::Features::RequirementLegacy', desc: 'Ultimate only.' },
                expose_nil: true

              expose_feature :status,
                using: ::API::Entities::WorkItems::Features::Status,
                documentation: { type: 'Entities::WorkItems::Features::Status', desc: 'Premium and Ultimate only.' },
                expose_nil: true

              expose_feature :verification_status,
                using: ::API::Entities::WorkItems::Features::VerificationStatus,
                documentation: { type: 'Entities::WorkItems::Features::VerificationStatus', desc: 'Ultimate only.' },
                expose_nil: true

              expose_feature :linked_items,
                using: ::API::Entities::WorkItems::Features::LinkedItems,
                documentation: {
                  type: 'Entities::WorkItems::Features::LinkedItems',
                  desc: 'Counts of blocking links. Blocking links are available in Premium and Ultimate only. ' \
                    'To list the linked items, use the linked_items endpoint.'
                },
                expose_nil: true

              expose_feature :custom_fields,
                using: ::API::Entities::WorkItems::Features::CustomFields,
                documentation: {
                  type: 'Entities::WorkItems::Features::CustomFields', desc: 'Premium and Ultimate only.'
                },
                expose_nil: true
            end
          end
        end
      end
    end
  end
end
