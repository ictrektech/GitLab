# frozen_string_literal: true

module Ai
  module DuoSettings
    # Foundational flows on a group's GitLab Duo settings page.
    class FoundationalFlowsPresenter
      # @param group [Group]
      def initialize(group)
        @group = group
      end

      # Whether the group readiness card renders. The flag rolls out per top-level group.
      #
      # @return [Boolean]
      def readiness_card_enabled?
        ::Feature.enabled?(:duo_group_agent_readiness_settings, root_ancestor, type: :wip)
      end

      # The flows the settings page lists. Only the top-level group picks flows, so a subgroup lists the
      # ones it picked, and none without the readiness card.
      #
      # @return [Array<Ai::Catalog::FoundationalFlow>]
      def listed_flows
        return available_flows if group.root?
        return [] unless readiness_card_enabled?

        picked_references = root_ancestor.selected_foundational_flow_references
        available_flows.select { |flow| picked_references.include?(flow.foundational_flow_reference) }
      end

      # The group's own selection, which the settings page sends back on save. A subgroup's stays empty
      # so that saving keeps its top-level group's flows.
      #
      # @return [Array<String>] foundational flow references
      def selected_flow_references
        return [] unless group.root?

        group.selected_foundational_flow_references
      end

      private

      attr_reader :group

      def available_flows
        ::Ai::Catalog::FoundationalFlow.available_for_group(root_ancestor)
      end

      def root_ancestor
        group.root_ancestor
      end
    end
  end
end
