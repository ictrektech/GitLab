# frozen_string_literal: true

module Security
  module SecurityOrchestrationPolicies
    class ResyncPoliciesService < ::BaseContainerService
      def execute
        if relationship == :direct
          policy_configuration = container.security_orchestration_policy_configuration

          return error(_('Policy project doesn\'t exist')) unless policy_configuration

          Security::SyncScanPoliciesWorker.perform_async(policy_configuration.id, SyncReason.to_params(:force_resync))
          return success
        end

        # TODO: Currently only project container is supported for inherited relationship,
        # after https://gitlab.com/gitlab-org/gitlab/-/issues/545805 is implemented,
        # we will call the worker for group_container.
        if project_container?
          # Reconciles group policy links, e.g. drops links an old transfer left to configurations that no longer apply.
          Security::Policies::GroupProjectTransferWorker.perform_async(container.id, current_user.id)

          container.all_security_orchestration_policy_configurations.each do |configuration|
            Security::SyncProjectPoliciesWorker.perform_async(container.id, configuration.id,
              SyncReason.to_params(:force_resync))
          end
        end

        success
      end

      private

      def relationship
        params[:relationship]
      end
    end
  end
end
