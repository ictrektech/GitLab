# frozen_string_literal: true

module Integrations
  module SlackWorkspace
    # What GitLab Duo needs in the Duo group to answer in Slack. The settings page and the refusal replies share it.
    class DuoRequirements
      # Credits need no seat. GitLab.com subscriptions belong to the top-level group, self-managed ones to the instance.
      def self.seats_required?(group)
        namespace = ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions) ? group : nil
        ::GitlabSubscriptions::AddOnPurchase.for_seat_assignable_duo_add_ons.active.by_namespace(namespace).exists?
      end

      def initialize(group)
        @group = group
      end

      def checks
        [
          check(:duo_features, duo_features_enabled?, :group_settings),
          check(:agent_platform, agent_platform_enabled?, agent_platform_fix),
          check(:experiment_features, experiment_features_enabled?, experiment_features_fix)
        ]
      end

      def duo_features_enabled?
        !!group.namespace_settings&.duo_features_enabled
      end

      def agent_platform_enabled?
        ::Ai::DuoWorkflow.duo_agent_platform_available?(group)
      end

      def experiment_features_enabled?
        group.duo_beta_flows_enabled?
      end

      def experiment_features_set_by_admin?
        !saas?
      end

      def agent_platform_set_by_admin?
        !saas?
      end

      private

      attr_reader :group

      def agent_platform_fix
        agent_platform_set_by_admin? ? :instance_settings : :group_settings
      end

      def experiment_features_fix
        experiment_features_set_by_admin? ? :instance_settings : :group_settings
      end

      def saas?
        ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      end

      def check(id, passed, fix)
        { id: id, ok: !!passed, fix: fix }
      end
    end
  end
end
