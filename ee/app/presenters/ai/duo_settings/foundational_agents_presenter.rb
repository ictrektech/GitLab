# frozen_string_literal: true

module Ai
  module DuoSettings
    # Foundational agents on a group's GitLab Duo settings page.
    class FoundationalAgentsPresenter
      # @param group [Group]
      # @param current_user [User]
      def initialize(group, current_user:)
        @group = group
        @current_user = current_user
      end

      # The agents the settings page lists. Like {Admin::AiConfigurationPresenter#foundational_agents_statuses}, it
      # hides the Orbit agent from users without Orbit, and the Ultimate-only agents without the license.
      #
      # @return [Array<Hash>] as {Ai::FoundationalAgentsStatusable#foundational_agents_statuses} returns them
      def listed_statuses
        statuses = group.root_ancestor.foundational_agents_statuses
        statuses = statuses.reject { |status| status[:reference] == 'orbit_agent' } unless orbit_enabled?
        return statuses if group.licensed_feature_available?(:ai_features)

        ultimate_only_references = ::Ai::FoundationalChatAgent.ultimate_only_references
        statuses.reject { |status| ultimate_only_references.include?(status[:reference]) }
      end

      private

      attr_reader :group, :current_user

      def orbit_enabled?
        ::Analytics::KnowledgeGraph.enabled_for?(current_user)
      end
    end
  end
end
