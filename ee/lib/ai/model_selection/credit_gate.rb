# frozen_string_literal: true

module Ai
  module ModelSelection
    class CreditGate
      include ::Gitlab::Utils::StrongMemoize

      def initialize(namespace)
        @namespace = namespace
      end

      def applies?
        return false unless ::Feature.enabled?(:restrict_credit_gated_models_on_trials, namespace)

        if ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
          trial_without_credits_namespace?
        else
          trial_without_credits_instance?
        end
      end
      strong_memoize_attr :applies?

      private

      attr_reader :namespace

      def trial_without_credits_namespace?
        return false unless namespace.is_a?(::Namespace)
        return false unless namespace.trial_active?
        return false unless ::Plan::FREE_TRIAL_PLANS.include?(namespace.actual_plan_name)

        !namespace.has_active_gitlab_credits_add_on?
      end

      def trial_without_credits_instance?
        return false unless ::License.current&.trial?

        ::License.billable_license.nil?
      end
    end
  end
end
