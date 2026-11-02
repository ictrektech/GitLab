# frozen_string_literal: true

module EE
  module Onboarding
    module FeatureLibrary
      module ExplorePagesBuilder
        extend ActiveSupport::Concern

        class_methods do
          extend ::Gitlab::Utils::Override

          override :available?
          def available?(user:, resource:)
            return false unless user && resource
            return false unless ::Feature.enabled?(:feature_catalog_explore_pages, resource.root_ancestor)

            user.can_admin_all_resources? || resource.member?(user)
          end
        end
      end
    end
  end
end
