# frozen_string_literal: true

module Gitlab
  module Scim
    class GroupSyncPatchService
      MEMBER_FILTER_PATH_REGEX = /\Amembers\[value\s+eq\s+"([^"]+)"\]\z/i
      MEMBERS_ATTRIBUTE = 'members'
      MEMBERS_FILTER_PATH_PREFIX = 'members['
      REPLACE_OPERATION = 'replace'
      FILTER_PATH_ERROR = 'Replacing group members with a filter path is not supported'
      COMBINED_REPLACE_ERROR = "Replacing group members can't be combined with other member changes in the same request"

      attr_reader :scim_group_uid, :operations

      def initialize(scim_group_uid:, operations:)
        @scim_group_uid = scim_group_uid
        @operations = operations
      end

      def execute
        return ServiceResponse.error(message: FILTER_PATH_ERROR) if replaces_members_with_filter_path?
        return ServiceResponse.error(message: COMBINED_REPLACE_ERROR) if replace_members_combined?

        operations.each do |operation|
          operation_type = operation[:op].to_s.downcase

          case operation_type
          when 'add'
            process_add_operation(operation)
          when 'remove'
            process_remove_operation(operation)
          when 'replace'
            process_replace_operation(operation)
          end
        end

        ServiceResponse.success
      end

      private

      def replaces_members_with_filter_path?
        operations.any? { |operation| replace_members_with_filter?(operation) }
      end

      def replace_members_with_filter?(operation)
        replace_operation?(operation) && members_filter_path?(operation)
      end

      def replace_operation?(operation)
        operation[:op].to_s.casecmp?(REPLACE_OPERATION)
      end

      def members_filter_path?(operation)
        operation[:path].to_s.downcase.start_with?(MEMBERS_FILTER_PATH_PREFIX)
      end

      # Each operation queues its own job and Sidekiq doesn't keep their order, so a members replace
      # next to another member change could leave a different result depending on which job runs first.
      def replace_members_combined?
        member_operations = operations.select { |operation| changes_members?(operation) }

        member_operations.size > 1 && member_operations.any? { |operation| replace_operation?(operation) }
      end

      def changes_members?(operation)
        path = operation[:path].to_s
        return path.downcase.start_with?(MEMBERS_ATTRIBUTE) if path.present?

        members_key(operation[:value]).present?
      end

      def process_add_operation(operation)
        case operation[:path].to_s.downcase
        when 'externalid'
          # NO-OP
          #
          # For now we just accept the externalId update but don't store it.
          # In some IdPs (e.g. Microsoft Entra), this is part of the group
          # sync provisioning cycle.
        when 'members'
          process_add_members(operation[:value])
        end
      end

      def process_remove_operation(operation)
        path = operation[:path].to_s

        case path.downcase
        when 'members'
          process_remove_members(operation[:value])
        else
          # Single member removal using a filter expression (RFC 7644 section 3.5.2.2),
          # e.g. members[value eq "<extern_uid>"], as sent by Okta.
          member_filter = path.match(MEMBER_FILTER_PATH_REGEX)
          process_remove_members([{ value: member_filter[1] }]) if member_filter
        end
      end

      def process_replace_operation(operation)
        case operation[:path].to_s.downcase
        when 'members'
          process_replace_members(operation[:value])
        when ''
          # RFC 7644 section 3.5.2.3 also allows the member list as a `members` key in a replace without a path.
          process_replace_members(members_from_value(operation[:value]))
        end
      end

      def members_from_value(value)
        key = members_key(value)
        value[key] if key
      end

      def members_key(value)
        return unless value.is_a?(Hash)

        value.keys.find { |key| key.to_s.casecmp?(MEMBERS_ATTRIBUTE) }
      end

      def process_add_members(members)
        return unless members.is_a?(Array)

        user_ids = collect_user_ids_from_members(members)
        return if user_ids.empty?

        ::Authn::SyncScimGroupMembersWorker.perform_async(scim_group_uid, user_ids, 'add')
      end

      def process_remove_members(members)
        return unless members.is_a?(Array)

        user_ids = collect_user_ids_from_members(members)
        return if user_ids.empty?

        ::Authn::SyncScimGroupMembersWorker.perform_async(scim_group_uid, user_ids, 'remove')
      end

      # Unlike add and remove, an empty list isn't skipped: replacing with no members removes
      # everyone synced through this SCIM group.
      def process_replace_members(members)
        return unless members.is_a?(Array)

        user_ids = collect_user_ids_from_members(members)

        ::Authn::SyncScimGroupMembersWorker.perform_async(scim_group_uid, user_ids, 'replace')
      end

      def collect_user_ids_from_members(members)
        extern_uids = members.filter_map { |member| member[:value] }
        return [] if extern_uids.empty?

        identities = ScimIdentity.for_instance.with_extern_uid(extern_uids)
        identities.filter_map(&:user_id)
      end
    end
  end
end
