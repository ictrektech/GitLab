# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module AdditionalContext
      # Builds agent_platform_bl_security_context
      # (schema: json_schemas/agent_platform/agent_platform_bl_security_context): the business
      # logic security scan's runtime dials, sourced from project CI/CD variables.
      #
      # Built at workflow start, so every start path (API, Duo Chat, restart and resume)
      # carries the dials.
      module BlSecurityContextBuilder
        CATEGORY = "agent_platform_bl_security_context"

        # Project CI/CD variable -> context key.
        SCAN_DIAL_VARIABLES = {
          'BL_SCAN_EFFORT' => 'scan_effort',
          'BL_TARGET_FILES' => 'target_files'
        }.freeze

        # scan_effort when BL_SCAN_EFFORT is unset, blank or not a known tier.
        DEFAULT_SCAN_EFFORT = 'low'

        # The engine's scan_effort tiers.
        SCAN_EFFORTS = %w[low standard high].freeze

        # nil for every flow other than the business logic security scan, and while the
        # flag is off, so the variables query is skipped for them.
        #
        # scan_effort is always sent (normalized, defaulting to low). target_files is sent
        # only when set, and only when the run checks out a branch other than the default
        # branch: BL_TARGET_FILES when set, otherwise (the goal being a merge request IID)
        # the files that merge request adds or modifies, if the run checks out that merge
        # request's own source branch. An absent key, not a null, marks it unset: the
        # schema types it as a string.
        #
        # Only unprotected, non-file variables in the `*` scope are read: a key may exist
        # once per environment scope, and a workflow has no environment when it starts.
        # Protected variables are meant for protected refs only.
        def self.build(project:, workflow_definition:, goal:, primary_branch:)
          return unless workflow_definition == ::Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE
          return unless ::Ai::Catalog::FoundationalFlow.bl_security_experimental.enabled_for?(project.root_ancestor)

          variables = project.variables.unprotected.env_var.by_environment_scope('*')
            .by_key(SCAN_DIAL_VARIABLES.keys)
          dials = variables.to_h { |variable| [SCAN_DIAL_VARIABLES[variable.key], variable.value] }.compact_blank

          dials['scan_effort'] = scan_effort(project, dials['scan_effort'])

          # A run that checks out the default branch ingests as a default-branch scan, so it
          # must stay a full scan, even with BL_TARGET_FILES set or a merge request IID goal.
          if primary_branch == project.default_branch_or_main
            dials = dials.except('target_files')
          else
            dials['target_files'] ||= merge_request_target_files(project, goal, primary_branch)
          end

          dials.compact
        end

        def self.scan_effort(project, value)
          return DEFAULT_SCAN_EFFORT if value.nil?

          normalized = value.strip.downcase
          return normalized if SCAN_EFFORTS.include?(normalized)

          ::Gitlab::AppJsonLogger.info(message: 'Business logic security scan: unknown BL_SCAN_EFFORT, using low',
            project_id: project.id, reason: 'invalid_scan_effort')
          DEFAULT_SCAN_EFFORT
        end
        private_class_method :scan_effort

        # Newline-separated paths, or nil to leave the field out, which makes the run a
        # whole-repository scan. The API and Duo Chat take the goal and the branch
        # separately, so the diff is used only when the run checks out the merge
        # request's own source branch.
        def self.merge_request_target_files(project, goal, primary_branch)
          result = ::Ai::Catalog::FoundationalFlow::BlSecurity::TargetFiles.for_goal(project: project, goal: goal)
          reason = result.reason
          reason = :branch_mismatch if result.paths && result.source_branch != primary_branch

          if reason
            ::Gitlab::AppJsonLogger.info(
              message: 'Business logic security scan target_files omitted, scanning the whole repository',
              project_id: project.id,
              merge_request_iid: goal.to_s,
              reason: reason.to_s
            )
            return
          end

          # Empty only for a deletion-only merge request, whose run the flow's goal
          # validator refuses before it gets here.
          result.paths.presence&.join("\n")
        end
        private_class_method :merge_request_target_files
      end
    end
  end
end
