# frozen_string_literal: true

module Govern
  module PolicyEngine
    # Builds the evaluation context document the settings triggers share.
    #
    # Every value is the project's own stored one, never what a group or the
    # instance would resolve it to. A project that is compliant only because
    # its group is strict still gets converged, and a later loosening of the
    # group creates no violation. `secret_push_protection_enabled` is left
    # out when the tier does not license it.
    #
    # `archived` is the stored column. `Project#archived` differs (scheduled
    # deletion, archived ancestors); reporting that effective state instead
    # is https://gitlab.com/gitlab-org/gitlab/-/work_items/633807.
    #
    # The document shape follows the GLAZ `project_settings` context schema,
    # registered under these trigger ids. A trigger without a registered
    # schema degrades to a diagnostic, not a failed evaluation.
    class ProjectSettingsContext
      SCHEMA_VERSION = '1-0-1'

      # Where the flat settings map sits in the built document.
      SETTINGS_PATH = %w[project settings].freeze

      # Everything the builder reads. Batch callers preload this list, so a
      # new association read below has to enter it too.
      PRELOAD_ASSOCIATIONS = %i[
        project_setting ci_cd_settings project_feature security_setting
        group namespace compliance_management_frameworks
      ].freeze

      def self.build(project:, trigger:, actor: nil)
        new(project: project, trigger: trigger, actor: actor).build
      end

      # The settings map on its own, for a caller that compares it against a
      # rule without sending a document to the engine.
      def self.settings_for(project)
        new(project: project, trigger: nil, actor: nil).settings
      end

      def initialize(project:, trigger:, actor:)
        @project = project
        @trigger = trigger
        @actor = actor
      end

      def build
        {
          'schema_version' => SCHEMA_VERSION,
          'evaluated_at' => Time.current.iso8601,
          'trigger' => trigger,
          'actor' => actor && "users/#{actor.id}",
          'organization' => { 'id' => "organizations/#{project.organization_id}" },
          'groups' => group_ancestor_ids,
          'compliance_frameworks' => compliance_framework_ids,
          'project' => {
            'id' => project.id,
            'full_path' => project.full_path,
            'personal' => project.personal?,
            'archived' => project.read_attribute(:archived),
            'namespace_id' => project.namespace_id,
            'settings' => settings
          }
        }.compact
      end

      def settings
        {
          'visibility' => project.visibility,
          'request_access_enabled' => project.read_attribute(:request_access_enabled),
          'only_allow_merge_if_pipeline_succeeds' =>
            project.read_attribute(:only_allow_merge_if_pipeline_succeeds),
          'only_allow_merge_if_all_discussions_are_resolved' =>
            project.read_attribute(:only_allow_merge_if_all_discussions_are_resolved),
          'remove_source_branch_after_merge' => project.read_attribute(:remove_source_branch_after_merge)
        }.merge(squash_setting, approval_settings, ci_cd_settings, feature_settings, security_settings)
      end

      private

      attr_reader :project, :trigger, :actor

      # A NULL enum column is no stored choice, so the key is left out rather
      # than emitted as a value outside the schema's enum.
      def squash_setting
        { 'squash_option' => project.project_setting.squash_option }.compact
      end

      def approval_settings
        ApprovalSettings::ENTRIES.to_h do |entry|
          value = project.read_attribute(entry.column)

          # A NULL column places no restriction, so every allow-term reads
          # true, agreeing with how the inverted entries already read NULL.
          [entry.setting, value.nil? || entry.convert(value)]
        end
      end

      def ci_cd_settings
        ci_cd = project.ci_cd_settings
        return {} unless ci_cd

        {
          'keep_latest_artifact' => ci_cd.read_attribute(:keep_latest_artifact),
          'allow_fork_pipelines_to_run_in_parent_project' =>
            ci_cd.read_attribute(:allow_fork_pipelines_to_run_in_parent_project),
          'pipeline_variables_minimum_override_role' => ci_cd.pipeline_variables_minimum_override_role
        }
      end

      def feature_settings
        feature = project.project_feature
        return {} unless feature

        {
          'merge_requests_access_level' => access_level_str(feature.merge_requests_access_level),
          'builds_access_level' => access_level_str(feature.builds_access_level),
          'forking_access_level' => access_level_str(feature.forking_access_level)
        }
      end

      # Project creation builds the row on any tier, so the license, not the
      # row, decides enforceability. An absent key has to mean "not
      # enforceable here", never a default the policy could act on.
      def security_settings
        return {} unless project.licensed_feature_available?(:secret_push_protection)

        security = project.security_setting
        return {} unless security

        { 'secret_push_protection_enabled' => security.secret_push_protection_enabled }
      end

      def access_level_str(level)
        ::Featurable::STRING_OPTIONS.key(level)
      end

      def group_ancestor_ids
        project.group ? project.group.self_and_ancestor_ids.sort : []
      end

      def compliance_framework_ids
        project.compliance_management_frameworks.map(&:id).sort
      end
    end
  end
end
