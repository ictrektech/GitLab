# frozen_string_literal: true

module EE
  module ReadonlyAbilities
    extend ActiveSupport::Concern

    READONLY_ABILITIES = %i[
      admin_tag
      push_to_delete_protected_branch
      create_merge_request_from
      create_merge_request_in
      admin_software_license_policy
      create_test_case
      create_package
      create_commit_status
      create_vulnerability_feedback
      update_vulnerability_feedback
      update_approvers
      create_release
      update_release
      admin_merge_request
      admin_snippet
      admin_wiki
      admin_pipeline
      admin_pipeline_schedule
      admin_build
      admin_trigger
      admin_environment
      admin_deployment
      admin_container_image
      admin_cluster
      admin_vulnerability
      admin_feature_flag
      admin_feature_flags_client
      admin_iteration
    ].freeze

    READONLY_FEATURES = %i[
      merge_request
      snippet
      wiki
      pipeline
      pipeline_schedule
      build
      trigger
      environment
      deployment
      container_image
      cluster
      vulnerability
      feature_flag
      feature_flags_client
      iteration
    ].freeze

    class_methods do
      def readonly_abilities
        READONLY_ABILITIES
      end

      def readonly_features
        READONLY_FEATURES
      end
    end
  end
end
