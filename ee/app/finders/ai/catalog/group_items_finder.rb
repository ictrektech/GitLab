# frozen_string_literal: true

module Ai
  module Catalog
    # Finds AI catalog items that a group can enable.
    #
    # Returns public items from the group's organization, and restricted items from within its
    # top-level group. Private items are never returned, as they can't be enabled for a group.
    #
    # Arguments:
    #   current_user - User performing the search (required for feature flag and permission checks)
    #   group - Group to find AI catalog items for
    #   params - Hash containing search parameters:
    #     :item_types - Array of item types to filter by. E.g.: ['agent', 'flow']
    #     :enabled_by - Array of enablement kinds. Returns items enabled by any of them:
    #                   - :inheritance: group inheritance-enabled items for the group.
    #                   - :project_direct: enabled directly in any descendant project in the group
    #     :search - String to search for in item name and description
    #     :sort - Sort key, one of Item::SORT_SCOPES
    #
    # Returns ActiveRecord::Relation
    class GroupItemsFinder < BaseContainerItemsFinder
      private

      alias_method :group, :container

      def authorized?
        Ability.allowed?(current_user, :read_ai_catalog_item, group)
      end

      def init_collection
        available_items
      end

      def enabled_consumers(kind)
        case kind
        when :inheritance then inheritance_consumers
        when :project_direct then project_direct_consumers
        end
      end

      # Only top-level groups can have inheritance records.
      def inheritance_consumers
        return unless group.root?
        return unless ::Feature.enabled?(:ai_catalog_group_inherited_consumers, root_ancestor)

        ItemConsumer.for_groups(group).inheritance.by_enabled(true)
      end

      def project_direct_consumers
        ItemConsumer.for_projects(group.all_projects).by_enabled(true)
      end
    end
  end
end
