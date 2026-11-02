# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Fans out one SyncNamespaceSessionCreditsWorker job per root namespace that had
    # Duo Agent Platform session activity inside the sync window, discovered from the
    # siphon copy of duo_workflows_workflows in ClickHouse so Postgres is never scanned.
    # Self-managed has one instance-level subscription and gets a single job.
    class SyncSessionCreditsCronWorker
      include ApplicationWorker
      include ClickHouseWorker
      # Disables retries: a retried run could overlap the next tick and double-enqueue.
      # A dropped tick costs nothing; the child resumes from its cursor on the next one.
      include ::CronjobQueue

      idempotent!
      deduplicate :until_executed
      data_consistency :sticky
      feature_category :value_stream_management
      urgency :low
      tags :clickhouse
      # Credits are never urgent; on a degraded namespaces table skip the tick.
      defer_on_database_health_signal :gitlab_main_org, [:namespaces]

      # Spreads the 6-hour tick's jobs one minute apart over its first 5.5 hours
      SPREAD_MINUTES = 330
      GROUP_LOAD_BATCH_SIZE = 1_000
      SIPHON_TABLE = 'duo_workflows_workflows'

      # Covers the 6-hour tick and CustomersDot's sync lag many times over.
      LOOKUP_ACTIVITY_WINDOW = 3.days

      ACTIVE_ROOT_NAMESPACES_QUERY = <<~SQL
        SELECT DISTINCT toUInt64OrZero(splitByChar('/', traversal_path)[2]) AS root_namespace_id
        FROM siphon_duo_workflows_workflows
        WHERE _siphon_watermark >= {window_start:DateTime64(6, 'UTC')}
          AND updated_at >= {window_start:DateTime64(6, 'UTC')}
      SQL

      def perform
        return unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?

        @enumerated = 0
        @enqueued = 0
        @flag_off = 0

        log_extra_metadata_on_done(:namespace_jobs_buffered, buffered_namespace_jobs)

        siphon_ready = !saas? || ::Gitlab::ClickHouse.siphon_enabled?(SIPHON_TABLE)
        enabled = enabled_root_namespaces if saas? && siphon_ready
        observe_freshness(enabled) if enabled

        @stop_reason =
          if siphon_ready
            saas? ? enqueue_root_namespaces(enabled) : enqueue_instance
            :completed
          else
            :siphon_disabled
          end

        log_extra_metadata_on_done(:namespaces_enumerated, @enumerated)
        log_extra_metadata_on_done(:namespaces_enqueued, @enqueued)
        log_extra_metadata_on_done(:namespaces_flag_off, @flag_off)
        log_extra_metadata_on_done(:stop_reason, @stop_reason)
      end

      private

      def enabled_root_namespaces
        groups = active_root_namespace_ids.each_slice(GROUP_LOAD_BATCH_SIZE).flat_map do |ids|
          ::Group.id_in(ids).with_route.to_a
        end
        enabled, disabled = groups.partition { |group| sync_enabled_for?(group) }
        @flag_off = disabled.size

        enabled
      end

      def observe_freshness(groups)
        stats = SessionCredits::SyncFreshness.observe(groups.map(&:id))

        stats&.each { |key, value| log_extra_metadata_on_done(key, value) }
      end

      def enqueue_root_namespaces(enabled)
        return if enabled.empty?

        buckets = [enabled.size, SPREAD_MINUTES].min

        # Round-robin, so every minute of the spread is used however many groups there are.
        enabled.each_with_index.group_by { |_, index| index % buckets }.each do |minute, pairs|
          bucket = pairs.map(&:first)

          if minute == 0
            SyncNamespaceSessionCreditsWorker.bulk_perform_async_with_contexts(bucket, **context_procs)
          else
            SyncNamespaceSessionCreditsWorker.bulk_perform_in_with_contexts(minute.minutes, bucket, **context_procs)
          end
        end

        @enqueued = enabled.size
      end

      def context_procs
        {
          arguments_proc: ->(group) { group.id },
          context_proc: ->(group) { { namespace: group } }
        }
      end

      def buffered_namespace_jobs
        ::Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService
          .queue_size(SyncNamespaceSessionCreditsWorker.name)
      end

      def enqueue_instance
        @enumerated = 1

        unless sync_enabled_for?(nil)
          @flag_off = 1
          return
        end

        SyncNamespaceSessionCreditsWorker.perform_async(nil)
        @enqueued = 1
      end

      def active_root_namespace_ids
        query = ::ClickHouse::Client::Query.new(
          raw_query: ACTIVE_ROOT_NAMESPACES_QUERY,
          placeholders: { window_start: LOOKUP_ACTIVITY_WINDOW.ago.utc.to_f }
        )

        ids = ::ClickHouse::Client.select(query, :main).filter_map do |row|
          id = row['root_namespace_id']
          id if id > 0
        end

        @enumerated = ids.size
        ids
      end

      # Self-managed jobs carry no namespace, so only the instance toggle applies.
      def sync_enabled_for?(group)
        Feature.enabled?(:duo_workflow_session_credits_sync_v2, group || :instance)
      end

      def saas?
        ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      end
    end
  end
end
