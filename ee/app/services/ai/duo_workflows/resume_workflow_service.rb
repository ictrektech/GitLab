# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class ResumeWorkflowService < StartWorkflowService
      include Gitlab::Utils::StrongMemoize

      # Emitted by git_environment_variables only on some paths, so a plain merge would
      # leave the previous job's behind: FF_GIT_URLS_WITHOUT_TOKENS when the flag was on
      # then off, and the higher GIT_CONFIG_* indices when the entry count shrinks.
      CONDITIONAL_GIT_ENV_KEYS = /\A(?:GIT_CONFIG_(?:KEY|VALUE)_\d+|FF_GIT_URLS_WITHOUT_TOKENS)\z/

      private

      def variables
        # Preserve job variables from initial workload; refresh token variables, and the
        # flow identity with them, since the token is bound to it.
        # Git config is recomputed rather than preserved: a resumed workflow is a new
        # pipeline with a fresh clone, and the commands that depend on it are recomputed
        # too, so carrying the previous job's GIT_CONFIG_* forward would let a
        # dap_git_credential_helper or dap_session_tracking_enabled? flip mid-workflow
        # leave the variables and the commands on opposite git-auth paths. The git
        # strategy variables are recomputed for the same reason, to match clone_commands.
        # A reference-repository job carried no runner-clone variables, so all of
        # git_clone_variables is recomputed for it in case the reference path is now off.
        previous_vars = previous_workload_variables
        return super if previous_vars.empty?

        skipped_checkout = previous_vars[:GIT_STRATEGY] == 'none'
        retry_variables = skipped_checkout ? {} : git_source_retry_variables
        git_strategy_variables =
          if skipped_checkout
            {}
          elsif previous_vars[:GIT_STRATEGY] == 'empty'
            git_clone_variables
          else
            git_strategy.variables
          end

        merged = previous_vars
          .except(:GET_SOURCES_ATTEMPTS, *previous_git_strategy_keys(previous_vars))
          .reject { |key, _| key.to_s.match?(CONDITIONAL_GIT_ENV_KEYS) }
          .merge(retry_variables)
          .merge(git_strategy_variables)
          .merge(git_environment_variables)
          .merge(token_variables)
          .merge(flow_identity_variables)
          # The resumed job rebuilds the sandbox wrapper, which references these by name.
          .merge(sandbox.environment_variables)

        # The preserved `DUO_WORKFLOW_GOAL` is stale from the first run, so a
        # resume carrying a fresh goal has to override it.
        merged[:DUO_WORKFLOW_GOAL] = workflow_goal if @params[:goal].present?
        merged
      end

      def executor_cli_command
        cmd = super
        # `human_approval` nil (vs true/false) means no approve/reject decision;
        # omit the flag instead so ai-gateway treats `goal` as the reply.
        cmd += %( --approval #{@params[:human_approval]}) unless @params[:human_approval].nil?
        if @params[:human_message].present?
          cmd += %( --rejection-reason #{Shellwords.shellescape(@params[:human_message])})
        end

        cmd
      end

      # Only a reference-repository job sets `empty`. GIT_LFS_SKIP_SMUDGE is kept because
      # the runner-clone path sets it too, so it stays correct whichever path resume takes.
      def previous_git_strategy_keys(previous_vars)
        return [] unless previous_vars[:GIT_STRATEGY] == 'empty'

        [:GIT_STRATEGY, ::Gitlab::DuoWorkflow::GitStrategy::REFERENCE_REPOSITORY_PATH_VARIABLE.to_sym]
      end

      def previous_workload_variables
        return {} unless previous_workflow_build

        previous_workflow_build.yaml_variables.to_h { |v| [v[:key].to_sym, v[:value]] }
      end

      def previous_workflow_build
        @workflow.last_workload&.pipeline&.builds&.order(:id)&.first
      end
      strong_memoize_attr :previous_workflow_build

      def ci_runtime_environment_key
        previous_workflow_build&.job_runtime_environment&.runtime_environment&.environment_key
      end

      # A resumed goal can be a user's free-text reply (see
      # ResumeWorkplanService), not the templated goal a fresh start carries.
      # The job trace is otherwise unmasked and often public, so this is not
      # echoed - same reasoning as DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT in
      # the parent class.
      def goal_echo_command
        nil
      end
    end
  end
end
