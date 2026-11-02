# frozen_string_literal: true

module API
  module Entities
    class CommitDetail < Commit
      include ::API::Helpers::Presentable
      include Gitlab::Utils::StrongMemoize

      expose :stats, using: ::API::Entities::CommitStats, if: ->(_, options) { options[:include_stats] && stats }
      expose :status_for, as: :status, documentation: { type: 'String', example: 'success' }
      expose :project_id, documentation: { type: 'Integer', format: 'int64', example: 1 }

      expose :last_pipeline, documentation: { type: ::API::Entities::Ci::PipelineBasic.to_s } do |commit, options|
        pipeline = commit.lazy_latest_pipeline if can_read_pipeline?
        ::API::Entities::Ci::PipelineBasic.represent(pipeline, options)
      end

      def self.execute_batch_counting(commits_relation)
        commits_relation.each(&:lazy_latest_pipeline)
      end

      private

      def stats
        object.stats
      rescue Gitlab::Git::CommandError => e
        raise unless ::Feature.enabled?(:commit_stats_failure_handling, object.project)

        Gitlab::ErrorTracking.log_exception(e, project_id: object.project_id, commit_id: object.id)
        nil
      end
      strong_memoize_attr :stats

      def can_read_pipeline?
        Ability.allowed?(options[:current_user], :read_pipeline, object.lazy_latest_pipeline)
      end
    end
  end
end
