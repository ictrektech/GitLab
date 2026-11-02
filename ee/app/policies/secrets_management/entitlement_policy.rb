# frozen_string_literal: true

module SecretsManagement
  class EntitlementPolicy < BasePolicy
    # A nil group is the instance-wide entitlement on GitLab Self-Managed.
    delegate { @subject.group || :global }
  end
end
