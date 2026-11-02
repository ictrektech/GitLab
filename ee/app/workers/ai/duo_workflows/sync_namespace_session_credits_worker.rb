# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Pulls the sessions CustomersDot changed since this root namespace's cursor and
    # upserts their credit totals into ClickHouse. One job per root namespace, or one
    # instance-level job on self-managed, fanned out by SyncSessionCreditsCronWorker.
    #
    # A classified failure never raises for Sidekiq to retry: the tick logs why and the
    # next tick resumes from the cursor (and the stored page token) it left behind. An
    # unclassified error still propagates, after the pages already fetched are written.
    class SyncNamespaceSessionCreditsWorker
      include ApplicationWorker
      # Registers migration pause control and the suspend_click_house_data_ingestion
      # kill switch, and declares the CustomersDot call as an external dependency.
      include ClickHouseWorker

      data_consistency :delayed
      idempotent!
      deduplicate :until_executed
      feature_category :value_stream_management
      # :throttled, not :low: concurrency_limit buffering counts toward :low's 60s
      # queueing SLO by design; :throttled has no queueing target.
      urgency :throttled
      tags :clickhouse
      loggable_arguments 0

      # Each job is an uncached ClickHouse scan on CustomersDot's side (INC-13873).
      concurrency_limit -> { 20 }

      # Wraps a transport failure on the CustomersDot call, so the rescue below can tell
      # it apart from the same error classes raised by the ClickHouse client.
      CustomersDotConnectionError = Class.new(StandardError)
      # hasNextPage true with no endCursor: following it would skip pages for good.
      MalformedResponseError = Class.new(StandardError)
      SyncFailure = Class.new(StandardError)
      # Retry-After is longer than the job has left; stop now and let the next tick resume.
      RateLimitWaitTooLong = Class.new(StandardError)

      MAX_RUNTIME = 120.seconds
      # One instance-level job drains the whole backlog on self-managed. The limit is
      # checked between pages, so leave a margin under the 5-minute :throttled target.
      SELF_MANAGED_MAX_RUNTIME = 4.minutes
      # Pages buffered into one ClickHouse INSERT; many small inserts hurt the merge tree.
      PAGES_PER_INSERT = 10
      # What each failure does to this namespace. Only CustomersDot's explicit signals change
      # the schedule; everything else is logged and counted, and the next tick retries from
      # the cursor and the stored page token.
      #   disabled      -> pause this source for PAUSE_DURATIONS[:disabled], no progression
      #   rate_limited  -> handled in fetch_page: wait inside the job and retry the page
      #   server_error, unavailable, connection_error, malformed_response, undefined_field,
      #   no_cdot_subscription_found, error, response_error, clickhouse_error, redis_error,
      #   invalid_rows  -> no pause
      PAUSE_DURATIONS = { disabled: 2.hours }.freeze
      # A 429 without Retry-After waits this long before the same page is asked for again.
      RATE_LIMIT_WAIT = 5.seconds
      # Not degradations, so not measured by the SLI: a field CustomersDot has not deployed,
      # a namespace it has no subscription for, and a self-managed instance without a license.
      SLI_UNMEASURED_REASONS = %w[undefined_field no_cdot_subscription_found no_billable_license].freeze

      def perform(root_namespace_id = nil)
        return unless ::Gitlab::ClickHouse.globally_enabled_for_analytics?
        return unless sync_enabled_for?(root_namespace_id)

        @root_namespace_id = root_namespace_id
        @stats = {
          pages_fetched: 0, rows_written: 0, calls_made: 0, rate_limit_waits: 0, failure_reason: '', cdot_synced_at: ''
        }
        @stop_reason = :error

        @stop_reason = sync
      rescue ::Sidekiq::Shutdown
        # Sidekiq re-queues the job, so the run is neither a success nor a failure.
        @stop_reason = :interrupted
        raise
      ensure
        if @stats
          record_sli
          log_done
        end
      end

      private

      attr_reader :root_namespace_id

      def sync
        return :backoff if SessionCredits::SyncPause.reason(source: pause_source)
        # A nil namespace on GitLab.com is a caller bug, not the instance-level case.
        return fail_with(:missing_root_namespace) if saas? && root_namespace_id.nil?
        return fail_with(:no_billable_license) unless client

        # Read inside the rescue: a ClickHouse outage here is a logged failure, not a retry.
        @cursor_before = cursor.value_us
        after = cursor.after_token
        @cursor_reseeded = cursor.reseeded?

        page_through(after)
      rescue RateLimitWaitTooLong
        # Named here so a failing flush in the ensure cannot claim the done line.
        @stats[:failure_reason] = 'rate_limited'
        count_failure(:rate_limited)
        :rate_limited
      rescue ::Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError => e
        fail_with(e.reason || :response_error, e)
      rescue CustomersDotConnectionError => e
        fail_with(:connection_error, e)
      rescue MalformedResponseError => e
        fail_with(:malformed_response, e)
      rescue ::ClickHouse::Client::DatabaseError, *::Gitlab::HTTP::HTTP_ERRORS => e
        # Only ClickHouse talks HTTP from here on; CustomersDot errors are wrapped above.
        fail_with(:clickhouse_error, e)
      rescue ::Redis::BaseError, ::RedisClient::Error => e
        fail_with(:redis_error, e)
      ensure
        flush_pending
      end

      # Pages are buffered into one INSERT. A page joins the buffer only once its token is
      # known, so whatever ends the loop the buffer holds complete pages and @after names
      # the page to read next; the cursor advances after every written buffer, so a long
      # drain always progresses.
      def page_through(after)
        limiter = ::Gitlab::Metrics::RuntimeLimiter.new(saas? ? MAX_RUNTIME : SELF_MANAGED_MAX_RUNTIME)
        @buffer = []
        @after = after
        buffered_pages = 0

        loop do
          page = fetch_page(@after, limiter)
          next_after = next_token(page[:page_info])
          @buffer.concat(Array(page[:sessions]))
          @after = next_after
          buffered_pages += 1

          next if @after && buffered_pages < PAGES_PER_INSERT && !limiter.over_time?

          failure = flush_buffer
          return fail_with(failure) if failure

          buffered_pages = 0

          return finish_window unless @after
          return :over_time if limiter.over_time?
        end
      end

      # Whatever ended the loop, the pages already fetched are written and the token that
      # follows them is kept, so no tick loses work. Its own failures are logged, not raised.
      def flush_pending
        failure = flush_buffer
        fail_with(failure) if failure
      rescue ::ClickHouse::Client::DatabaseError, *::Gitlab::HTTP::HTTP_ERRORS => e
        fail_with(:clickhouse_error, e)
      rescue ::Redis::BaseError, ::RedisClient::Error => e
        fail_with(:redis_error, e)
      end

      # Writes the buffer, then moves the cursor and stores the token, in that order. The
      # buffer is handed off before the write, so a failed write is never retried from
      # flush_pending. Returns the ingest failure reason, nil when nothing was pending.
      def flush_buffer
        return if @buffer.blank?

        pending = @buffer
        @buffer = []
        failure = write(pending)
        return failure if failure

        # Pages arrive in updatedAt order, so everything up to the newest written row is
        # read; advancing now keeps the progress even if the token is later dropped.
        cursor.advance!(@max_updated_at_us)
        cursor.store_after_token(@after) if @after

        nil
      end

      # A 429 is waited out here, inside the job's runtime budget, so a throttled namespace
      # keeps draining instead of losing the tick. Nothing is paused for it.
      def fetch_page(after, limiter)
        @stats[:calls_made] += 1
        page = client.get_sessions(updated_after: cursor.updated_after, after: after)
        @stats[:pages_fetched] += 1
        @stats[:cdot_synced_at] = page[:synced_at].to_s

        page
      rescue ::Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError => e
        raise unless e.reason == :rate_limited

        wait = e.retry_after || RATE_LIMIT_WAIT.to_i
        raise RateLimitWaitTooLong if wait >= limiter.max_runtime - limiter.elapsed_time

        @stats[:rate_limit_waits] += 1
        sleep(wait)
        retry
      rescue *::Gitlab::HTTP::HTTP_ERRORS => e
        raise CustomersDotConnectionError, "#{e.class}: #{e.message}"
      end

      # Returns the failure reason, or nil once the buffer is written.
      def write(nodes)
        response = SessionCredits::IngestService.new(nodes: nodes).execute
        return response.reason if response.error?

        @stats[:rows_written] += response.payload[:rows_written]
        @max_updated_at_us = [@max_updated_at_us, response.payload[:max_updated_at_us]].compact.max

        nil
      end

      def finish_window
        cursor.clear_after_token
        # Only GitLab.com namespaces are tracked; self-managed has no freshness SLI.
        SessionCredits::SyncFreshness.record_completion(root_namespace_id) if root_namespace_id

        :completed
      end

      def next_token(page_info)
        return unless page_info.is_a?(Hash) && page_info[:hasNextPage] == true

        page_info[:endCursor].presence || raise(MalformedResponseError, 'hasNextPage without an endCursor')
      end

      def fail_with(reason, error = nil)
        # The failure that ended the tick names the done line; a later flush failure is
        # still logged and counted below.
        @stats[:failure_reason] = reason.to_s if @stats[:failure_reason].empty?

        # CustomersDot has no credits for a namespace it has no subscription for, so there
        # is nothing to go stale.
        if reason == :no_cdot_subscription_found && root_namespace_id
          SessionCredits::SyncFreshness.record_completion(root_namespace_id)
        end

        duration = PAUSE_DURATIONS[reason]
        SessionCredits::SyncPause.pause!(source: pause_source, reason: reason, duration: duration) if duration

        # The client already reports its own ResponseError; everything else is ours.
        unless error.is_a?(::Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)
          ::Gitlab::ErrorTracking.track_exception(
            error || SyncFailure.new(reason.to_s), root_namespace_id: root_namespace_id, reason: reason.to_s
          )
        end

        count_failure(reason)

        ::Gitlab::AppLogger.warn(
          Labkit::Fields::CLASS_NAME => self.class.name,
          Labkit::Fields::LOG_MESSAGE => 'Failed to sync session credits',
          Labkit::Fields::GL_ROOT_NAMESPACE_ID => root_namespace_id,
          Labkit::Fields::ERROR_TYPE => reason.to_s,
          Labkit::Fields::ERROR_MESSAGE => error&.message
        )

        :error
      end

      # Built inside the method: a class-body metric is evaluated at constantize
      # time and breaks server_metrics_spec.
      def count_failure(reason)
        ::Gitlab::Metrics.counter(
          :duo_workflow_session_credits_v2_fetch_failures_total,
          'Total failed v2 CustomersDot session syncs'
        ).increment(reason: reason.to_s)
      end

      # Reads the cursor again only if the first read succeeded; by then the value is
      # memoized, so this never touches ClickHouse from the ensure block.
      def log_done
        @stats.each { |key, value| log_extra_metadata_on_done(key, value) }
        log_extra_metadata_on_done(:root_namespace_id, root_namespace_id)
        log_extra_metadata_on_done(:cursor_before, @cursor_before.to_i)
        log_extra_metadata_on_done(:cursor_after, @cursor_before ? cursor.value_us : 0)
        log_extra_metadata_on_done(:cursor_lag_s, cursor_lag_s)
        log_extra_metadata_on_done(:cursor_reseeded, @cursor_reseeded == true)
        log_extra_metadata_on_done(:cdot_sync_lag_s, cdot_sync_lag_s)
        log_extra_metadata_on_done(:stop_reason, @stop_reason)
      end

      # A paused source makes no attempt, and a rate limit heals on the next tick, so neither is
      # measured. Only a drained window or progress cut off by the budget counts as a success.
      def record_sli
        return if @stop_reason.in?(%i[backoff interrupted rate_limited])
        return if SLI_UNMEASURED_REASONS.include?(@stats[:failure_reason])

        ::Gitlab::Metrics::DuoWorkflowSessionCreditsSyncSlis.record(error: !@stop_reason.in?(%i[completed over_time]))
      end

      def cursor_lag_s
        return 0 unless @cursor_before

        [Time.current.to_i - cursor.position_time.to_i, 0].max
      end

      def cdot_sync_lag_s
        synced_at = Time.iso8601(@stats[:cdot_synced_at])

        [Time.current.to_i - synced_at.to_i, 0].max
      rescue ArgumentError
        0
      end

      def cursor
        @cursor ||= SessionCredits::Cursor.new(root_namespace_id)
      end

      # Self-managed has one instance-level subscription keyed by license.
      def client
        return @client if defined?(@client)

        @client =
          if saas?
            ::Gitlab::SubscriptionPortal::SubscriptionUsageClient.new(namespace_id: root_namespace_id)
          else
            license_key = ::License.billable_license&.data
            license_key && ::Gitlab::SubscriptionPortal::SubscriptionUsageClient.new(license_key: license_key)
          end
      end

      def saas?
        ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
      end

      def pause_source
        root_namespace_id&.to_s || 'instance'
      end

      # Self-managed jobs carry no namespace, so only the instance toggle applies.
      def sync_enabled_for?(root_namespace_id)
        return Feature.enabled?(:duo_workflow_session_credits_sync_v2, :instance) unless root_namespace_id

        Feature.enabled?(:duo_workflow_session_credits_sync_v2, ::Group.actor_from_id(root_namespace_id))
      end
    end
  end
end
