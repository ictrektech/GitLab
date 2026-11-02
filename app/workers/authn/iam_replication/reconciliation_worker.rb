# frozen_string_literal: true

module Authn
  module IamReplication
    class ReconciliationWorker
      include ApplicationWorker
      include CronjobQueue # rubocop:disable Scalability/CronWorkerContext -- instance-wide sweep, no context

      idempotent!
      deduplicate :until_executed, including_scheduled: true
      # Replicas may lag up to 60s, the Layer 3 delay: a stale read could overwrite a newer Layer 3 write.
      data_consistency :always # rubocop:disable SidekiqLoadBalancing/WorkerDataConsistency -- see comment above
      feature_category :system_access
      urgency :low
      worker_has_external_dependencies!
      # One job per entity type, so the sweeps do not block each other.
      concurrency_limit -> { ::Authn::IamOutbox::ALLOWED_ENTITY_TYPES.size }
      loggable_arguments 0
      defer_on_database_health_signal(:gitlab_main, [], 5.minutes) do |job_args, schema|
        entity_type = job_args.first
        scanned_table = ::Authn::IamReplication.replicator_for(entity_type).reconciliation_scope.table_name

        [schema, [scanned_table]]
      end

      # Shorter than the cron interval (5 minutes), so runs do not overlap.
      MAX_RUNTIME = 4.minutes
      BATCH_SIZE = 200
      # BulkUpsertClients takes at most 1000 records. Per-record sweeps keep BATCH_SIZE to save the cursor often.
      BULK_BATCH_SIZE = 1000
      REDIS_LAST_PROCESSED_ID_TTL = 14.days
      # Any other reason means IAM is unhealthy: re-raise, and the next run retries from the last processed id.
      ROW_LEVEL_REASONS = %i[invalid_request failed_precondition].freeze

      def perform(entity_type)
        return unless ::Authn::IamReplication.enabled? && ::Authn::IamAuthService.enabled?

        @entity_type = entity_type
        @replicator = ::Authn::IamReplication.replicator_for(entity_type).new
        runtime_limiter = Gitlab::Metrics::RuntimeLimiter.new(MAX_RUNTIME)
        counts = Hash.new(0)

        begin
          cursor = last_processed_id
          scope = replicator.class.reconciliation_scope
          # rubocop:disable CodeReuse/ActiveRecord -- scan owned by this worker
          # Filter inside the batch, like OauthAccessTokenArchiveWorker, so the bounds use only the primary key.
          scope.klass.where('id > ?', cursor).each_batch(of: batch_size) do |batch|
            upsert_batch(batch.merge(scope), counts)
            last_batch_id = batch.maximum(:id)
            # rubocop:enable CodeReuse/ActiveRecord
            save_last_processed_id(last_batch_id) if last_batch_id

            break if runtime_limiter.over_time?
          end

          # Not over time means each_batch ran out of rows: the pass is complete, so the next run starts over.
          save_last_processed_id(0) unless runtime_limiter.was_over_time?
        ensure
          # In ensure, so a run that IAM stops also logs how far it got.
          log_extra_metadata_on_done(:result, counts.merge(
            rows: counts.values.sum,
            entity_type: entity_type,
            layer: 4,
            cell_id: Gitlab.config.cell.id.to_i,
            over_time: runtime_limiter.was_over_time?,
            last_processed_id: cursor
          ))
        end
      end

      private

      attr_reader :entity_type, :replicator

      def batch_size
        bulk? ? BULK_BATCH_SIZE : BATCH_SIZE
      end

      def bulk?
        replicator.respond_to?(:bulk_upsert)
      end

      def upsert_batch(records, counts)
        if bulk?
          replicator.bulk_upsert(records).each do |record, outcome, message, iam_reason|
            unless outcome == ::Authn::IamReplication::Results::DELIVERED
              log_skipped_row(record, outcome, message, iam_reason)
            end

            counts[outcome] += 1
          end
        else
          # Refresh tokens get a bulk RPC with https://gitlab.com/gitlab-org/gitlab/-/work_items/635782.
          records.each { |record| counts[upsert(record)] += 1 }
        end
      end

      def upsert(record)
        replicator.upsert(record)
      rescue ::Authn::IamService::GrpcClient::RequestError => error
        raise unless ROW_LEVEL_REASONS.include?(error.reason)

        log_skipped_row(record, error.reason)
        error.reason
      rescue StandardError => error
        Gitlab::ErrorTracking.track_exception(error, entity_type: entity_type, entity_id: record.id)
        ::Authn::IamReplication::Results::ERROR
      end

      def log_skipped_row(record, reason, message = nil, iam_reason = nil)
        ::Gitlab::AuthLogger.warn(
          build_structured_payload_labkit(
            message: 'IAM reconciliation row skipped',
            layer: 4,
            entity_type: entity_type,
            entity_id: record.id,
            skip_reason: reason,
            skip_message: message,
            skip_iam_reason: iam_reason
          ).compact
        )
      end

      def last_processed_id
        Gitlab::Redis::SharedState.with { |redis| redis.get(redis_key).to_i }
      end

      def save_last_processed_id(processed_id)
        Gitlab::Redis::SharedState.with { |redis| redis.set(redis_key, processed_id, ex: REDIS_LAST_PROCESSED_ID_TTL) }
      end

      def redis_key
        "authn:iam_replication:reconciliation:last_processed_id:#{entity_type}"
      end
    end
  end
end
