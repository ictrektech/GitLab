# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SyncNamespaceSessionCreditsWorker, :click_house, :clean_gitlab_redis_shared_state,
  :freeze_time, feature_category: :value_stream_management do
  let_it_be(:group) { create(:group) }

  let(:root_namespace_id) { group.id }
  let(:client) { instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient) }
  let(:cursor) { Ai::DuoWorkflows::SessionCredits::Cursor.new(root_namespace_id) }
  let(:pause) { Ai::DuoWorkflows::SessionCredits::SyncPause }
  let(:response_error) { Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError }
  let(:synced_at) { 5.minutes.ago.utc.iso8601(6) }

  let(:first_updated_at) { Time.utc(2026, 10, 8, 10, 15, 0) }
  let(:second_updated_at) { Time.utc(2026, 10, 8, 10, 16, 0, 1) }
  let(:newest_us) { (second_updated_at.to_r * 1_000_000).to_i }

  let(:nodes) do
    [
      node(11, '1.5', first_updated_at, models: ['claude-sonnet']),
      node(12, '20', second_updated_at, models: ['gpt-4o'])
    ]
  end

  let(:worker) { described_class.new }

  subject(:perform) { worker.perform(root_namespace_id) }

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
    allow(Gitlab::Saas).to receive(:feature_available?).and_call_original
    allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(true)
    allow(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to receive(:new).and_return(client)
    allow(client).to receive(:get_sessions).and_return(page(nodes))
    allow(worker).to receive(:log_extra_metadata_on_done).and_call_original
  end

  def node(id, credits, updated_at, models: [])
    {
      workflowId: id.to_s,
      creditsUsed: credits,
      modelsUsed: models,
      updatedAt: updated_at.iso8601(6),
      creditsByModel: models.map { |model| { model: model, creditsUsed: credits } }
    }
  end

  def page(nodes, has_next: false, end_cursor: nil)
    {
      success: true,
      sessions: nodes,
      page_info: { hasNextPage: has_next, endCursor: end_cursor },
      synced_at: synced_at
    }
  end

  def stored_rows
    ClickHouse::Client.select(<<~SQL, :main)
      SELECT workflow_id, credits_used
      FROM duo_workflow_session_enrichments FINAL
      ORDER BY workflow_id
    SQL
  end

  def stored_cursor
    ClickHouse::SyncCursor.cursor_for(cursor.key)
  end

  def expect_logged(key, value)
    expect(worker).to have_received(:log_extra_metadata_on_done).with(key, value)
  end

  # Writes a cursor row with an earlier recorded_at, so the job's own advance wins the argMax.
  def record_cursor(micros, at:)
    ClickHouse::Client.execute(ClickHouse::Client::Query.new(
      raw_query: ClickHouse::SyncCursor::INSERT_CURSOR_QUERY,
      placeholders: { primary_key_value: micros, table_name: cursor.key, recorded_at: at.to_f }
    ), :main)
  end

  def expect_failure_counted(reason)
    counter = instance_double(Prometheus::Client::Counter)
    allow(Gitlab::Metrics).to receive(:counter).and_call_original
    allow(Gitlab::Metrics).to receive(:counter)
      .with(:duo_workflow_session_credits_v2_fetch_failures_total, anything).and_return(counter)
    expect(counter).to receive(:increment).with(reason: reason)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [root_namespace_id] }

    it 'leaves one row per session however many times it runs' do
      perform_idempotent_work

      expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
    end
  end

  describe 'a cold start' do
    it 'asks CustomersDot for the seed window and writes the page' do
      perform

      expect(client).to have_received(:get_sessions)
        .with(updated_after: Ai::DuoWorkflows::SessionCredits::Cursor.seed_time, after: nil)
      expect(stored_rows).to eq([
        { 'workflow_id' => 11, 'credits_used' => BigDecimal('1.5') },
        { 'workflow_id' => 12, 'credits_used' => BigDecimal(20) }
      ])
    end

    it 'advances the cursor to the newest updatedAt written' do
      perform

      expect(stored_cursor).to eq(newest_us)
    end

    it 'authenticates by namespace on GitLab.com' do
      perform

      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to have_received(:new)
        .with(namespace_id: root_namespace_id)
    end

    it 'logs the done-line contract', :aggregate_failures do
      perform

      expect_logged(:root_namespace_id, root_namespace_id)
      expect_logged(:pages_fetched, 1)
      expect_logged(:rows_written, 2)
      expect_logged(:calls_made, 1)
      expect_logged(:rate_limit_waits, 0)
      expect_logged(:cursor_before, 0)
      expect_logged(:cursor_after, newest_us)
      expect_logged(:cursor_lag_s, Time.current.to_i - second_updated_at.to_i)
      expect_logged(:stop_reason, :completed)
      expect_logged(:failure_reason, '')
      expect_logged(:cdot_synced_at, synced_at)
      expect_logged(:cdot_sync_lag_s, 5.minutes.to_i)
      expect_logged(:cursor_reseeded, false)
    end
  end

  describe 'a warm cursor' do
    let(:stored) { Time.utc(2026, 10, 7, 9, 0, 0, 250_000) }

    before do
      cursor.advance!((stored.to_r * 1_000_000).to_i)
    end

    it 'resumes from the stored cursor' do
      perform

      expect(client).to have_received(:get_sessions).with(updated_after: stored, after: nil)
    end

    it 'logs the previous position' do
      perform

      expect_logged(:cursor_before, (stored.to_r * 1_000_000).to_i)
    end
  end

  describe 'paging' do
    let(:second_page_nodes) { [node(13, '3', second_updated_at + 1.second)] }

    before do
      allow(client).to receive(:get_sessions).with(hash_including(after: nil))
        .and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
      allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
        .and_return(page(second_page_nodes))
    end

    it 'follows endCursor until hasNextPage is false, writes once and advances once', :aggregate_failures do
      expect(Ai::DuoWorkflows::SessionCredits::IngestService).to receive(:new).once.and_call_original

      perform

      expect(client).to have_received(:get_sessions).twice
      expect(stored_rows.pluck('workflow_id')).to match_array([11, 12, 13])
      expect(stored_cursor).to eq(((second_updated_at + 1.second).to_r * 1_000_000).to_i)
      expect(cursor.after_token).to be_nil
      expect_logged(:pages_fetched, 2)
      expect_logged(:calls_made, 2)
    end

    it 'clears the token once the window is drained' do
      perform

      expect(Gitlab::Redis::SharedState.with { |redis| redis.exists?(cursor.after_token_key) }).to be(false)
    end

    it 'resumes a partly drained window from its token with the pinned window, not the advanced cursor' do
      window = Ai::DuoWorkflows::SessionCredits::Cursor.seed_time
      record_cursor(newest_us, at: 1.minute.ago)
      Gitlab::Redis::SharedState.with do |redis|
        redis.set(cursor.after_token_key, Gitlab::Json.dump({ c: 'cursor-1', u: (window.to_r * 1_000_000).to_i }))
      end

      perform

      expect(client).to have_received(:get_sessions).once.with(updated_after: window, after: 'cursor-1')
    end

    it 'resumes from a token stored for the current window' do
      cursor.store_after_token('cursor-1')

      perform

      expect(client).to have_received(:get_sessions).once
        .with(updated_after: Ai::DuoWorkflows::SessionCredits::Cursor.seed_time, after: 'cursor-1')
    end

    it 'limits a GitLab.com job to the namespace runtime budget' do
      expect(Gitlab::Metrics::RuntimeLimiter).to receive(:new).with(described_class::MAX_RUNTIME).and_call_original

      perform
    end

    context 'when the runtime budget runs out between pages' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
      end

      it 'advances the cursor past what it wrote and keeps the token for the next tick', :aggregate_failures do
        perform

        expect(client).to have_received(:get_sessions).once
        expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
        expect(stored_cursor).to eq(newest_us)
        expect(cursor.after_token).to eq('cursor-1')
        expect_logged(:stop_reason, :over_time)
        expect_logged(:cursor_after, newest_us)
      end
    end

    context 'when hasNextPage is true but endCursor is blank' do
      before do
        allow(client).to receive(:get_sessions).and_return(page(nodes, has_next: true, end_cursor: ''))
      end

      it 'fails as a malformed response instead of advancing past unread pages', :aggregate_failures do
        expect_failure_counted('malformed_response')

        perform

        expect(client).to have_received(:get_sessions).once
        expect(stored_rows).to be_empty
        expect(stored_cursor).to eq(0)
        expect_logged(:failure_reason, 'malformed_response')
      end

      context 'when earlier pages were fetched cleanly' do
        before do
          allow(client).to receive(:get_sessions).with(hash_including(after: nil))
            .and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
            .and_return(page(second_page_nodes, has_next: true, end_cursor: ''))
        end

        it 'writes them and keeps the token of the malformed page, so it is re-read next tick', :aggregate_failures do
          perform

          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
          expect(stored_cursor).to eq(newest_us)
          expect(cursor.after_token).to eq('cursor-1')
          expect_logged(:failure_reason, 'malformed_response')
        end
      end
    end
  end

  describe 'rate limiting' do
    let(:rate_limited) { response_error.new('slow down', reason: :rate_limited, retry_after: 3) }
    let(:second_page_nodes) { [node(13, '3', second_updated_at + 1.second)] }

    before do
      allow(worker).to receive(:sleep)
      allow(client).to receive(:get_sessions).with(hash_including(after: nil))
        .and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
      # First call for the second page is throttled, the retry succeeds.
      allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
        .and_invoke(->(*) { raise rate_limited }, ->(*) { page(second_page_nodes) })
    end

    it 'waits for Retry-After, retries the same page and finishes the window', :aggregate_failures do
      perform

      expect(worker).to have_received(:sleep).with(3).once
      expect(client).to have_received(:get_sessions).with(hash_including(after: 'cursor-1')).twice
      expect(stored_rows.pluck('workflow_id')).to match_array([11, 12, 13])
      expect(cursor.after_token).to be_nil
      expect_logged(:stop_reason, :completed)
      expect_logged(:calls_made, 3)
      expect_logged(:rate_limit_waits, 1)
      expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
    end

    context 'when the response carries no Retry-After' do
      let(:rate_limited) { response_error.new('slow down', reason: :rate_limited) }

      it 'waits the default few seconds' do
        perform

        expect(worker).to have_received(:sleep).with(described_class::RATE_LIMIT_WAIT.to_i).once
      end
    end

    context 'when Retry-After is longer than the runtime left' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:elapsed_time).and_return(described_class::MAX_RUNTIME.to_i - 2)
        end
      end

      it 'writes what it holds, stores the token and stops without sleeping', :aggregate_failures do
        expect_failure_counted('rate_limited')

        perform

        expect(worker).not_to have_received(:sleep)
        expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
        expect(stored_cursor).to eq(newest_us)
        expect(cursor.after_token).to eq('cursor-1')
        expect_logged(:stop_reason, :rate_limited)
        expect_logged(:failure_reason, 'rate_limited')
        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end

      context 'when the flush is rejected too' do
        before do
          allow(ClickHouse::Client).to receive(:insert_csv).and_raise(ClickHouse::Client::DatabaseError, 'nope')
        end

        it 'keeps rate_limited as the reason and logs the insert failure', :aggregate_failures do
          expect(Gitlab::AppLogger).to receive(:warn)
            .with(hash_including(Labkit::Fields::ERROR_TYPE => 'clickhouse_error'))

          perform

          expect(stored_cursor).to eq(0)
          expect(cursor.after_token).to be_nil
          expect_logged(:stop_reason, :rate_limited)
          expect_logged(:failure_reason, 'rate_limited')
        end
      end
    end

    context 'when Retry-After equals the runtime left' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:elapsed_time).and_return(described_class::MAX_RUNTIME.to_i - 3)
        end
      end

      it 'stops rather than sleeping into the budget', :aggregate_failures do
        perform

        expect(worker).not_to have_received(:sleep)
        expect_logged(:stop_reason, :rate_limited)
      end
    end

    context 'when the first page is throttled and there is no time to wait' do
      before do
        allow(client).to receive(:get_sessions).with(hash_including(after: nil)).and_raise(rate_limited)
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:elapsed_time).and_return(described_class::MAX_RUNTIME.to_i - 2)
        end
      end

      it 'stops with nothing written and nothing stored', :aggregate_failures do
        perform

        expect(stored_rows).to be_empty
        expect(stored_cursor).to eq(0)
        expect(cursor.after_token).to be_nil
        expect_logged(:stop_reason, :rate_limited)
      end
    end
  end

  describe 'a page without pageInfo' do
    before do
      allow(client).to receive(:get_sessions).and_return(page(nodes).merge(page_info: nil))
    end

    it 'is treated as the last page: written, cursor advanced, token cleared', :aggregate_failures do
      cursor.store_after_token('stale')

      perform

      expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
      expect(stored_cursor).to eq(newest_us)
      expect(cursor.after_token).to be_nil
      expect_logged(:stop_reason, :completed)
    end
  end

  describe 'an empty page' do
    before do
      allow(client).to receive(:get_sessions).and_return(page([]))
    end

    it 'completes without moving the cursor', :aggregate_failures do
      perform

      expect(stored_cursor).to eq(0)
      expect_logged(:rows_written, 0)
      expect_logged(:stop_reason, :completed)
    end
  end

  describe 'gates' do
    context 'when ClickHouse analytics is disabled' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it 'does not call CustomersDot' do
        perform

        expect(client).not_to have_received(:get_sessions)
      end
    end

    context 'when the flag is disabled' do
      before do
        stub_feature_flags(duo_workflow_session_credits_sync_v2: false)
      end

      it 'does not call CustomersDot, so buffered jobs drain harmlessly after a flip' do
        perform

        expect(client).not_to have_received(:get_sessions)
      end
    end

    context 'when the flag is enabled for another group only' do
      before do
        stub_feature_flags(duo_workflow_session_credits_sync_v2: create(:group))
      end

      it 'does not call CustomersDot' do
        perform

        expect(client).not_to have_received(:get_sessions)
      end
    end

    context 'when this namespace is paused' do
      before do
        pause.pause!(source: root_namespace_id.to_s, reason: :disabled, duration: 2.hours)
      end

      it 'skips the tick and says so', :aggregate_failures do
        perform

        expect(client).not_to have_received(:get_sessions)
        expect_logged(:stop_reason, :backoff)
        expect_logged(:failure_reason, '')
      end
    end

    context 'when another namespace is paused' do
      before do
        pause.pause!(source: (root_namespace_id + 1).to_s, reason: :disabled, duration: 2.hours)
      end

      it 'still syncs, since a pause never spreads' do
        perform

        expect(client).to have_received(:get_sessions)
      end
    end

    context 'when a GitLab.com job carries no root namespace' do
      let(:root_namespace_id) { nil }

      it 'fails instead of falling back to instance-level behaviour', :aggregate_failures do
        expect_failure_counted('missing_root_namespace')

        perform

        expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).not_to have_received(:new)
        expect_logged(:failure_reason, 'missing_root_namespace')
      end
    end

    context 'when the stored cursor fell out of the CustomersDot window' do
      before do
        # Recorded a minute earlier so the sync_cursors argMax prefers the advance made by the job.
        ClickHouse::Client.execute(ClickHouse::Client::Query.new(
          raw_query: ClickHouse::SyncCursor::INSERT_CURSOR_QUERY,
          placeholders: {
            primary_key_value: (91.days.ago.to_r * 1_000_000).to_i,
            table_name: cursor.key,
            recorded_at: 1.minute.ago.to_f
          }
        ), :main)
      end

      it 'reseeds inside the window, syncs and says so', :aggregate_failures do
        perform

        expect(client).to have_received(:get_sessions)
          .with(updated_after: Ai::DuoWorkflows::SessionCredits::Cursor.seed_time, after: nil)
        expect(stored_cursor).to eq(newest_us)
        expect_logged(:cursor_reseeded, true)
        expect_logged(:stop_reason, :completed)
      end
    end

    context 'when a stored page token carries a window that fell out of the CustomersDot limit' do
      before do
        stale_window = (Ai::DuoWorkflows::SessionCredits::Cursor.token_window_floor - 1.second).to_r * 1_000_000
        Gitlab::Redis::SharedState.with do |redis|
          redis.set(cursor.after_token_key, Gitlab::Json.dump({ c: 'expired-token', u: stale_window.to_i }))
        end
      end

      it 'drops the token, reseeds the window and says so', :aggregate_failures do
        perform

        expect(client).to have_received(:get_sessions)
          .with(updated_after: Ai::DuoWorkflows::SessionCredits::Cursor.seed_time, after: nil)
        expect_logged(:cursor_reseeded, true)
        expect_logged(:stop_reason, :completed)
      end

      context 'when earlier ticks had already advanced the cursor inside the window' do
        let(:advanced_at) { Time.utc(2026, 10, 1, 12, 0, 0) }

        before do
          record_cursor((advanced_at.to_r * 1_000_000).to_i, at: 1.minute.ago)
        end

        it 'continues from the advanced cursor without a token, keeping the progress', :aggregate_failures do
          perform

          expect(client).to have_received(:get_sessions).with(updated_after: advanced_at, after: nil)
          expect_logged(:cursor_reseeded, false)
          expect_logged(:stop_reason, :completed)
        end
      end
    end

    context 'when ClickHouse is down before the first read' do
      before do
        allow(ClickHouse::SyncCursor).to receive(:cursor_for).and_raise(ClickHouse::Client::DatabaseError, 'down')
      end

      it 'does not raise for Sidekiq and still logs the done line', :aggregate_failures do
        expect_failure_counted('clickhouse_error')

        expect { perform }.not_to raise_error

        expect(client).not_to have_received(:get_sessions)
        expect_logged(:stop_reason, :error)
        expect_logged(:failure_reason, 'clickhouse_error')
        expect_logged(:cursor_before, 0)
        expect_logged(:cursor_after, 0)
      end
    end

    context 'when Redis is down' do
      before do
        allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(Redis::ConnectionError, 'down')
      end

      it 'does not raise for Sidekiq and reports a redis failure', :aggregate_failures do
        expect_failure_counted('redis_error')

        expect { perform }.not_to raise_error

        expect_logged(:stop_reason, :error)
        expect_logged(:failure_reason, 'redis_error')
      end
    end
  end

  describe 'self-managed' do
    let(:root_namespace_id) { nil }

    before do
      allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
      allow(License).to receive(:billable_license).and_return(instance_double(License, data: 'license-data'))
    end

    it 'authenticates with the license key and uses the instance cursor', :aggregate_failures do
      perform

      expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient).to have_received(:new)
        .with(license_key: 'license-data')
      expect(ClickHouse::SyncCursor.cursor_for('duo_workflow_session_credits_v2_instance')).to eq(newest_us)
    end

    it 'gives the single instance job the longer self-managed runtime budget' do
      expect(Gitlab::Metrics::RuntimeLimiter).to receive(:new)
        .with(described_class::SELF_MANAGED_MAX_RUNTIME).and_call_original

      perform
    end

    context 'when CustomersDot asks for a wait that only fits the self-managed budget' do
      let(:long_wait) { described_class::MAX_RUNTIME.to_i + 10 }

      before do
        allow(worker).to receive(:sleep)
        allow(client).to receive(:get_sessions)
          .and_invoke(->(*) { raise response_error.new('slow', reason: :rate_limited, retry_after: long_wait) },
            ->(*) { page(nodes) })
      end

      it 'waits it out, since the instance job has four minutes', :aggregate_failures do
        perform

        expect(worker).to have_received(:sleep).with(long_wait).once
        expect_logged(:stop_reason, :completed)
      end
    end

    context 'when the instance flag is off' do
      before do
        stub_feature_flags(duo_workflow_session_credits_sync_v2: false)
      end

      it 'does not call CustomersDot' do
        perform

        expect(client).not_to have_received(:get_sessions)
      end
    end

    context 'when CustomersDot has the kill switch on' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('off', reason: :disabled))
      end

      it 'pauses the instance, since that is the only source there' do
        perform

        expect(pause.reason(source: 'instance')).to eq(:disabled)
      end
    end

    context 'when there is no billable license' do
      before do
        allow(License).to receive(:billable_license).and_return(nil)
      end

      it 'fails without calling CustomersDot', :aggregate_failures do
        expect_failure_counted('no_billable_license')

        perform

        expect(client).not_to have_received(:get_sessions)
        expect_logged(:failure_reason, 'no_billable_license')
      end
    end
  end

  describe 'failures' do
    shared_examples 'a failed tick' do |reason|
      it "stops with #{reason}, writes nothing and keeps the cursor", :aggregate_failures do
        expect_failure_counted(reason)
        expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
          Labkit::Fields::LOG_MESSAGE => 'Failed to sync session credits',
          Labkit::Fields::ERROR_TYPE => reason
        ))

        expect { perform }.not_to raise_error

        expect(stored_cursor).to eq(0)
        expect_logged(:stop_reason, :error)
        expect_logged(:failure_reason, reason)
      end
    end

    context 'when CustomersDot reports a server error' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('boom', reason: :server_error))
      end

      it_behaves_like 'a failed tick', 'server_error'

      it 'does not pause the namespace, since a 5xx is CustomersDot\'s to fix' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when CustomersDot has the kill switch on' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('off', reason: :disabled))
      end

      it_behaves_like 'a failed tick', 'disabled'

      it 'pauses this namespace for two hours flat', :aggregate_failures do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to eq(:disabled)
        ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(pause.key(root_namespace_id.to_s)) }
        expect(ttl).to be_between(2.hours.to_i - 5, 2.hours.to_i)
        expect(pause.reason(source: (root_namespace_id + 1).to_s)).to be_nil
      end
    end

    context 'when CustomersDot does not expose the field yet' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('nope', reason: :undefined_field))
      end

      it_behaves_like 'a failed tick', 'undefined_field'

      it 'does not pause the namespace' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when CustomersDot has no subscription for the namespace' do
      before do
        allow(client).to receive(:get_sessions)
          .and_raise(response_error.new('none', reason: :no_cdot_subscription_found))
      end

      it_behaves_like 'a failed tick', 'no_cdot_subscription_found'

      it 'does not pause the namespace' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when the connection fails' do
      before do
        allow(client).to receive(:get_sessions).and_raise(Errno::ECONNREFUSED)
      end

      it_behaves_like 'a failed tick', 'connection_error'

      it 'does not pause the namespace' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when ClickHouse refuses the connection during the insert' do
      before do
        allow(ClickHouse::Client).to receive(:insert_csv).and_raise(Errno::ECONNREFUSED)
      end

      it_behaves_like 'a failed tick', 'clickhouse_error'

      it 'does not blame CustomersDot for a ClickHouse connection error' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when ClickHouse rejects the insert' do
      before do
        allow(ClickHouse::Client).to receive(:insert_csv).and_raise(ClickHouse::Client::DatabaseError, 'down')
      end

      it_behaves_like 'a failed tick', 'clickhouse_error'

      it 'does not blame CustomersDot' do
        perform

        expect(pause.reason(source: root_namespace_id.to_s)).to be_nil
      end
    end

    context 'when a page carries an unparsable workflow id' do
      let(:nodes) { [node('not-an-id', '1', first_updated_at)] }

      it_behaves_like 'a failed tick', 'invalid_rows'

      it 'writes none of the page' do
        perform

        expect(stored_rows).to be_empty
      end

      it 'reports the bad page to error tracking, since it will fail every tick until fixed' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(kind_of(StandardError), hash_including(root_namespace_id: root_namespace_id, reason: 'invalid_rows'))

        perform
      end
    end

    context 'when a later page fails' do
      before do
        allow(client).to receive(:get_sessions).with(hash_including(after: nil))
          .and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
        allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
          .and_raise(response_error.new('boom', reason: :server_error))
      end

      it 'writes the pages it already holds and stores the token of the failed page', :aggregate_failures do
        perform

        expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
        expect(stored_cursor).to eq(newest_us)
        expect(cursor.after_token).to eq('cursor-1')
        expect_logged(:pages_fetched, 1)
        expect_logged(:rows_written, 2)
        expect_logged(:calls_made, 2)
        expect_logged(:stop_reason, :error)
        expect_logged(:failure_reason, 'server_error')
      end

      it 'resumes from that token on the next tick without re-reading the first page', :aggregate_failures do
        perform
        allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
          .and_return(page([node(13, '3', second_updated_at + 1.second)]))

        described_class.new.perform(root_namespace_id)

        expect(stored_rows.pluck('workflow_id')).to match_array([11, 12, 13])
        expect(client).to have_received(:get_sessions).with(hash_including(after: nil)).once
      end

      context 'when the connection drops instead' do
        before do
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
            .and_raise(Errno::ECONNREFUSED)
        end

        it 'flushes the same way', :aggregate_failures do
          perform

          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
          expect(cursor.after_token).to eq('cursor-1')
          expect_logged(:failure_reason, 'connection_error')
        end
      end

      context 'when the flush itself is rejected by ClickHouse' do
        before do
          allow(ClickHouse::Client).to receive(:insert_csv).and_raise(ClickHouse::Client::DatabaseError, 'nope')
        end

        it 'logs the insert failure, keeps the fetch failure as the reason, and leaves the cursor and token alone',
          :aggregate_failures do
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'server_error'))
          expect(Gitlab::AppLogger).to receive(:warn)
            .with(hash_including(Labkit::Fields::ERROR_TYPE => 'clickhouse_error'))

          perform

          expect(stored_cursor).to eq(0)
          expect(cursor.after_token).to be_nil
          expect_logged(:failure_reason, 'server_error')
          expect_logged(:rows_written, 0)
        end
      end

      context 'when the kill switch comes on mid-window' do
        before do
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
            .and_raise(response_error.new('off', reason: :disabled))
        end

        it 'pauses the namespace and still keeps the pages it fetched', :aggregate_failures do
          perform

          expect(pause.reason(source: root_namespace_id.to_s)).to eq(:disabled)
          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
          expect(cursor.after_token).to eq('cursor-1')
          expect_logged(:failure_reason, 'disabled')
        end
      end

      context 'when Redis fails while the token is being stored' do
        before do
          allow_next_instance_of(Ai::DuoWorkflows::SessionCredits::Cursor) do |instance|
            allow(instance).to receive(:store_after_token).and_raise(::Redis::ConnectionError)
          end
        end

        it 'keeps the written rows and the advanced cursor, logs the Redis failure, and does not raise',
          :aggregate_failures do
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'server_error'))
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'redis_error'))

          expect { perform }.not_to raise_error

          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
          expect(stored_cursor).to eq(newest_us)
          expect(cursor.after_token).to be_nil
          expect_logged(:failure_reason, 'server_error')
        end
      end

      context 'when the client raises something unclassified' do
        before do
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
            .and_raise(NoMethodError, 'nil')
        end

        it 'keeps the pages it fetched and the token, then lets Sidekiq see the error', :aggregate_failures do
          expect { perform }.to raise_error(NoMethodError)

          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12])
          expect(stored_cursor).to eq(newest_us)
          expect(cursor.after_token).to eq('cursor-1')
          expect_logged(:stop_reason, :error)
        end
      end

      context 'when the buffered rows are rejected by the ingest service' do
        let(:nodes) { [node('not-an-id', '1.5', first_updated_at)] }

        it 'reports both failures, keeps the fetch failure as the reason, and leaves the cursor and token alone',
          :aggregate_failures do
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'server_error'))
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(Labkit::Fields::ERROR_TYPE => 'invalid_rows'))

          perform

          expect(stored_rows).to be_empty
          expect(stored_cursor).to eq(0)
          expect(cursor.after_token).to be_nil
          # The failure that ended the tick is the one the done line names; the flush failure is logged.
          expect_logged(:failure_reason, 'server_error')
          expect_logged(:stop_reason, :error)
        end
      end

      context 'when buffers were already written in the loop' do
        before do
          stub_const("#{described_class}::PAGES_PER_INSERT", 1)
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-1'))
            .and_return(page([node(13, '3', second_updated_at + 1.second)], has_next: true, end_cursor: 'cursor-2'))
          allow(client).to receive(:get_sessions).with(hash_including(after: 'cursor-2'))
            .and_raise(response_error.new('boom', reason: :server_error))
        end

        it 'keeps every written buffer and the token of the page that failed', :aggregate_failures do
          expect(ClickHouse::Client).to receive(:insert_csv).twice.and_call_original

          perform

          expect(stored_rows.pluck('workflow_id')).to match_array([11, 12, 13])
          # Both advances share the frozen recorded_at, so read the job's own last advance.
          expect_logged(:cursor_after, ((second_updated_at + 1.second).to_r * 1_000_000).to_i)
          expect(cursor.after_token).to eq('cursor-2')
          expect_logged(:rows_written, 3)
        end
      end
    end
  end

  describe 'freshness' do
    let(:freshness) { Ai::DuoWorkflows::SessionCredits::SyncFreshness }

    before do
      allow(freshness).to receive(:record_completion)
    end

    it 'records the completion once the window is drained' do
      perform

      expect(freshness).to have_received(:record_completion).with(root_namespace_id).once
    end

    context 'when the runtime budget runs out' do
      before do
        allow(client).to receive(:get_sessions).and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
      end

      it 'records nothing, since the window is not drained yet' do
        perform

        expect(freshness).not_to have_received(:record_completion)
      end
    end

    context 'when the sync fails' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('boom', reason: :server_error))
      end

      it 'records nothing' do
        perform

        expect(freshness).not_to have_received(:record_completion)
      end
    end

    context 'when CustomersDot has no subscription for the namespace' do
      before do
        allow(client).to receive(:get_sessions)
          .and_raise(response_error.new('none', reason: :no_cdot_subscription_found))
      end

      it 'records a completion, since there are no credits to go stale' do
        perform

        expect(freshness).to have_received(:record_completion).with(root_namespace_id).once
      end
    end

    context 'when CustomersDot does not expose the field yet' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('nope', reason: :undefined_field))
      end

      it 'records nothing, so the missing field shows as stale data' do
        perform

        expect(freshness).not_to have_received(:record_completion)
      end
    end

    context 'on self-managed' do
      let(:root_namespace_id) { nil }

      before do
        allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
        allow(License).to receive(:billable_license).and_return(instance_double(License, data: 'license-data'))
      end

      it 'records nothing, since only GitLab.com namespaces are tracked' do
        perform

        expect(freshness).not_to have_received(:record_completion)
      end
    end
  end

  describe 'error rate SLI' do
    let(:sli) { Gitlab::Metrics::DuoWorkflowSessionCreditsSyncSlis }

    before do
      allow(sli).to receive(:record)
    end

    it 'records a success when the window is drained' do
      perform

      expect(sli).to have_received(:record).with(error: false).once
    end

    context 'when the runtime budget runs out' do
      before do
        allow(client).to receive(:get_sessions).and_return(page(nodes, has_next: true, end_cursor: 'cursor-1'))
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
      end

      it 'records a success, since the job made progress' do
        perform

        expect(sli).to have_received(:record).with(error: false).once
      end
    end

    context 'when the sync fails' do
      before do
        allow(client).to receive(:get_sessions).and_raise(response_error.new('boom', reason: :server_error))
      end

      it 'records an error' do
        perform

        expect(sli).to have_received(:record).with(error: true).once
      end
    end

    context 'when a GitLab.com job carries no root namespace' do
      let(:root_namespace_id) { nil }

      it 'records an error' do
        perform

        expect(sli).to have_received(:record).with(error: true).once
      end
    end

    context 'when the write fails' do
      before do
        allow_next_instance_of(Ai::DuoWorkflows::SessionCredits::IngestService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'bad', reason: :invalid_rows))
        end
      end

      it 'records an error' do
        perform

        expect(sli).to have_received(:record).with(error: true).once
      end
    end

    context 'when an unexpected error escapes the job' do
      before do
        allow(client).to receive(:get_sessions).and_raise(ArgumentError, 'boom')
      end

      it 'records an error' do
        expect { perform }.to raise_error(ArgumentError)

        expect(sli).to have_received(:record).with(error: true).once
      end
    end

    context 'when Sidekiq shuts down mid-job' do
      before do
        allow(client).to receive(:get_sessions).and_raise(Sidekiq::Shutdown)
      end

      it 'records nothing, since Sidekiq re-queues the job', :aggregate_failures do
        expect { perform }.to raise_error(Sidekiq::Shutdown)

        expect(sli).not_to have_received(:record)
        expect_logged(:stop_reason, :interrupted)
      end
    end

    context 'when the namespace is paused by the CustomersDot kill switch' do
      before do
        pause.pause!(source: root_namespace_id.to_s, reason: :disabled, duration: 2.hours)
      end

      it 'records nothing, since no sync was attempted' do
        perform

        expect(sli).not_to have_received(:record)
      end
    end

    context 'when CustomersDot rate limits for longer than the job has left' do
      before do
        allow(client).to receive(:get_sessions)
          .and_raise(response_error.new('slow down', reason: :rate_limited, retry_after: 1.hour.to_i))
      end

      it 'records nothing, since the next tick resumes from the stored token' do
        perform

        expect(sli).not_to have_received(:record)
      end
    end

    context 'when a self-managed instance has no billable license' do
      let(:root_namespace_id) { nil }

      before do
        allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
        allow(License).to receive(:billable_license).and_return(nil)
      end

      it 'records nothing, since a missing license is a configuration state, not a sync failure' do
        perform

        expect(sli).not_to have_received(:record)
      end
    end

    context 'when the failure is not a degradation' do
      where(:reason) { %i[undefined_field no_cdot_subscription_found] }

      with_them do
        before do
          allow(client).to receive(:get_sessions).and_raise(response_error.new('nope', reason: reason))
        end

        it 'records nothing' do
          perform

          expect(sli).not_to have_received(:record)
        end
      end
    end
  end

  describe 'worker attributes' do
    it 'registers with ClickHouse migration pause control' do
      expect(described_class.click_house_worker_attrs).to be_present
    end

    it 'bounds outbound CustomersDot pressure with a concurrency limit' do
      stub_feature_flags(sidekiq_concurrency_limit_middleware: true)

      expect(described_class.get_concurrency_limit).to eq(20)
    end

    it 'does not defer on Postgres health, since it reads only CustomersDot, ClickHouse and Redis' do
      expect(described_class.defer_on_database_health_signal?).to be(false)
    end

    it 'is throttled and deduplicated until executed', :aggregate_failures do
      expect(described_class.get_urgency).to eq(:throttled)
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
      expect(described_class.get_tags).to include(:clickhouse)
    end
  end
end
