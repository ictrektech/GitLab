# frozen_string_literal: true

module Ai
  module DuoWorkflow
    # Read-only view of how ready a group is to run Duo Agent Platform flows, backing
    # the readiness rows in the group GitLab Duo settings.
    class GroupReadiness
      include Readiness::RunnerCheck
      include Readiness::McpServers

      def initialize(group, user)
        @group = group
        @user = user
      end

      private

      attr_reader :group, :user

      alias_method :container, :group

      # With runner restrictions on, only instance runners and the root group's own
      # runners can pass RunnerValidator, so scanning the rest of the hierarchy would
      # only fill the candidate window with rejects.
      def runner_scope
        return ::Ci::Runner.usable_from_scope(group) unless Feature.enabled?(:duo_runner_restrictions, group)

        ::Ci::Runner.from_union(
          [group.shared_runners, ::Ci::Runner.belonging_to_group(group.root_ancestor.id)],
          remove_duplicates: false
        )
      end

      def mcp_consumer_params
        { group_id: group.id }
      end

      def mcp_block_namespace
        group
      end
    end
  end
end
