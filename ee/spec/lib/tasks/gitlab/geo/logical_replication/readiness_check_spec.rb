# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tasks::Gitlab::Geo::LogicalReplication::ReadinessCheck, :aggregate_failures, feature_category: :geo_replication do
  subject(:result) { check.execute }

  let(:check) do
    described_class.new(
      subscriber: subscriber,
      publisher_connection_string: publisher_connection_string,
      publication_name: 'geo_publication',
      subscription_name: 'geo_subscription',
      catch_up_timeout: catch_up_timeout,
      poll_interval: 0,
      connect_retry_interval: 0,
      block_on_writers: block_on_writers
    )
  end

  let(:block_on_writers) { false }
  let(:masked_sessions) { '0' }
  let(:sessions_by_call) { [[]] }

  let(:publisher_connection_string) { 'postgresql://primary/gitlabhq_production' }
  let(:catch_up_timeout) { 10 }
  let(:subscription_row) { { 'oid' => '16400', 'subenabled' => 't', 'subslotname' => 'geo_subscription' } }
  let(:target_row) { { 'in_recovery' => 'f', 'pubviaroot' => 't', 'slot_exists' => 't' } }
  let(:published) { [%w[public projects], %w[public p_ci_builds]] }
  let(:subscribed) { [%w[public projects r], %w[public p_ci_builds r]] }
  let(:error_counts) { [0] }
  let(:progress_row) { { 'caught_up' => 't', 'lag_bytes' => '0' } }
  let(:progress_by_call) { [progress_row] }
  let(:apply_worker_running) { 't' }

  let(:subscriber) { instance_double(PG::Connection) }
  let(:publisher) { instance_double(PG::Connection, close: nil, exec: nil, user: 'gitlab_replicator') }

  def pg_result(rows)
    instance_double(PG::Result, first: rows.first, values: rows, to_a: rows)
  end

  def session(state:, writes: false)
    {
      'pid' => '4242', 'usename' => 'gitlab', 'application_name' => 'puma', 'client_addr' => '10.0.0.5',
      'state' => state, 'holds_write_transaction' => writes ? 't' : 'f', 'transaction_age_seconds' => '3',
      'query' => 'UPDATE projects SET updated_at = now()'
    }
  end

  before do
    counts = error_counts.dup
    session_batches = sessions_by_call.dup
    progress_batches = progress_by_call.dup

    allow(subscriber).to receive(:exec_params) do |sql, _params|
      case sql
      when described_class::SUBSCRIPTION_SQL then pg_result([subscription_row].compact)
      when described_class::ERROR_COUNT_SQL
        pg_result([{ 'error_count' => (counts.size > 1 ? counts.shift : counts.first).to_s }])
      when described_class::SUBSCRIBED_RELATIONS_SQL then pg_result(subscribed)
      when described_class::APPLY_WORKER_SQL then pg_result([{ 'running' => apply_worker_running }])
      end
    end

    allow(publisher).to receive(:exec_params) do |sql, _params|
      case sql
      when described_class::PUBLISHER_TARGET_SQL then pg_result([target_row])
      when described_class::PUBLISHED_RELATIONS_SQL then pg_result(published)
      when described_class::CURRENT_LSN_SQL then pg_result([{ 'lsn' => '0/16B3748' }])
      when described_class::SLOT_PROGRESS_SQL
        pg_result([progress_batches.size > 1 ? progress_batches.shift : progress_batches.first])
      when described_class::MASKED_SESSIONS_SQL then pg_result([{ 'masked_sessions' => masked_sessions }])
      when described_class::SESSIONS_SQL
        pg_result(session_batches.size > 1 ? session_batches.shift : session_batches.first)
      end
    end

    allow(PG).to receive(:connect).and_return(publisher)
  end

  context 'when the subscriber has caught up with every published relation' do
    it 'is ready and does not block' do
      expect(result.status).to eq(:ready)
      expect(result).not_to be_blocking
      expect(result.message).to include('Subscription geo_subscription is ready to drop')
      expect(result.message).not_to include('publish_via_partition_root')
    end

    it 'bounds every publisher query with a session statement timeout and closes the connection' do
      result

      expect(PG).to have_received(:connect).with(
        publisher_connection_string, hash_including(application_name: described_class::APPLICATION_NAME)
      )
      expect(publisher).to have_received(:exec).with(
        "SET statement_timeout = #{described_class::STATEMENT_TIMEOUT_MS}; " \
          "SET lock_timeout = #{described_class::LOCK_TIMEOUT_MS}"
      )
      expect(publisher).to have_received(:close)
    end

    it 'waits for the WAL position the publisher had when the wait started' do
      result

      expect(publisher).to have_received(:exec_params)
        .with(described_class::SLOT_PROGRESS_SQL, %w[geo_subscription 0/16B3748])
    end
  end

  context 'when the publication does not publish partitions through their root' do
    let(:target_row) { { 'in_recovery' => 'f', 'pubviaroot' => 'f', 'slot_exists' => 't' } }

    it 'is ready, with a warning' do
      expect(result.status).to eq(:ready)
      expect(result.message).to include('was created without publish_via_partition_root')
    end
  end

  context 'when the connection returns typed values, like an ActiveRecord raw connection' do
    let(:subscription_row) { { 'oid' => 16400, 'subenabled' => true, 'subslotname' => 'geo_subscription' } }
    let(:target_row) { { 'in_recovery' => false, 'pubviaroot' => true, 'slot_exists' => true } }
    let(:progress_row) { { 'caught_up' => true, 'lag_bytes' => 0 } }

    it 'is ready' do
      expect(result.status).to eq(:ready)
      expect(result.message).not_to include('publish_via_partition_root')
    end

    context 'when the subscription is disabled' do
      let(:subscription_row) { { 'oid' => 16400, 'subenabled' => false, 'subslotname' => 'geo_subscription' } }

      it 'blocks' do
        expect(result.status).to eq(:subscription_disabled)
      end
    end
  end

  context 'when an earlier drop already detached the slot' do
    let(:subscription_row) { { 'oid' => '16400', 'subenabled' => 'f', 'subslotname' => nil } }

    it 'does not block the retry, and does not connect to the publisher' do
      expect(result.status).to eq(:slot_detached)
      expect(result).not_to be_blocking
      expect(result.message).to include('cannot be checked', 'GEO_SKIP_REPLICATION_CHECK=1', 'slot_name = NONE')
      expect(PG).not_to have_received(:connect)
    end
  end

  context 'when the subscription does not exist' do
    let(:subscription_row) { nil }

    it 'blocks without connecting to the publisher' do
      expect(result.status).to eq(:no_subscription)
      expect(result).to be_blocking
      expect(PG).not_to have_received(:connect)
    end
  end

  context 'when the subscription is disabled' do
    let(:subscription_row) { { 'oid' => '16400', 'subenabled' => 'f', 'subslotname' => 'geo_subscription' } }

    it 'blocks without connecting to the publisher, because the subscriber cannot catch up' do
      expect(result.status).to eq(:subscription_disabled)
      expect(result).to be_blocking
      expect(result.message).to include('subscription:enable')
      expect(PG).not_to have_received(:connect)
    end
  end

  context 'when GEO_PUBLISHER_CONNECTION_STRING is unset' do
    let(:publisher_connection_string) { nil }

    it 'blocks and points at the override' do
      expect(result.status).to eq(:not_configured)
      expect(result).to be_blocking
      expect(result.message).to include('GEO_SKIP_REPLICATION_CHECK=1')
      expect(PG).not_to have_received(:connect)
    end
  end

  context 'when the publisher is unreachable' do
    before do
      allow(PG).to receive(:connect).and_raise(PG::ConnectionBad, 'could not connect to server')
    end

    it 'blocks, because nothing was verified' do
      expect(result.status).to eq(:unreachable)
      expect(result).to be_blocking
      expect(result.message)
        .to include('PG::ConnectionBad: could not connect to server', 'GEO_PUBLISHER_CONNECTION_STRING')
    end

    it 'retries the connection first' do
      result

      expect(PG).to have_received(:connect).exactly(described_class::CONNECT_ATTEMPTS).times
    end
  end

  context 'when the publisher rejects the connection' do
    before do
      allow(PG).to receive(:connect)
        .and_raise(PG::ConnectionBad, 'FATAL:  password authentication failed for user "gitlab_replicator"')
    end

    it 'blocks and reports the error' do
      expect(result.status).to eq(:unreachable)
      expect(result).to be_blocking
      expect(result.message).to include('password authentication failed')
    end
  end

  context 'when the connection drops while setting the session timeouts' do
    let(:dropped) { instance_double(PG::Connection) }

    where(error: [PG::ConnectionBad, PG::UnableToSend])

    with_them do
      before do
        closed = false
        allow(dropped).to receive(:exec).and_raise(error, 'server closed the connection unexpectedly')
        allow(dropped).to receive(:close) do
          raise PG::ConnectionBad, 'connection is closed' if closed

          closed = true
        end

        attempts = 0
        allow(PG).to receive(:connect) do
          attempts += 1
          raise PG::ConnectionBad, 'could not connect to server' if attempts > 1

          dropped
        end
      end

      it 'closes that connection once and reports the publisher as unreachable' do
        expect(result.status).to eq(:unreachable)
        expect(result.message).to include('could not connect to server')
        expect(dropped).to have_received(:close).once
      end
    end
  end

  context 'when the publisher connection is lost during the wait' do
    before do
      allow(publisher).to receive(:exec_params)
        .with(described_class::SLOT_PROGRESS_SQL, anything)
        .and_raise(PG::UnableToSend, 'server closed the connection unexpectedly')
    end

    it 'blocks and reports the publisher as unreachable' do
      expect(result.status).to eq(:unreachable)
      expect(result).to be_blocking
      expect(result.message).to include('PG::UnableToSend')
    end
  end

  context 'when a publisher query waits on a lock' do
    before do
      allow(publisher).to receive(:exec_params)
        .with(described_class::PUBLISHED_RELATIONS_SQL, anything)
        .and_raise(PG::LockNotAvailable, 'canceling statement due to lock timeout')
    end

    it 'raises instead of treating the publisher as unreachable' do
      expect { result }.to raise_error(PG::LockNotAvailable)
    end
  end

  context 'when the slot disappears during the wait' do
    before do
      allow(publisher).to receive(:exec_params)
        .with(described_class::SLOT_PROGRESS_SQL, anything).and_return(pg_result([]))
    end

    it 'blocks and says the slot is gone' do
      expect(result.status).to eq(:wrong_target)
      expect(result.message).to include('it has no replication slot named geo_subscription')
    end
  end

  context 'when a publisher query times out' do
    before do
      allow(publisher).to receive(:exec_params)
        .with(described_class::PUBLISHER_TARGET_SQL, anything).and_raise(PG::QueryCanceled, 'statement timeout')
    end

    it 'blocks instead of treating the publisher as unreachable, and closes the connection', :aggregate_failures do
      expect(result.status).to eq(:publisher_timed_out)
      expect(result).to be_blocking
      expect(result.message).to include('did not answer within 5000ms', 'PG::QueryCanceled')
      expect(publisher).to have_received(:close)
    end
  end

  context 'when the publisher answers with an error' do
    before do
      allow(publisher).to receive(:exec_params)
        .with(described_class::PUBLISHED_RELATIONS_SQL, anything)
        .and_raise(PG::InsufficientPrivilege, 'permission denied')
    end

    it 'raises, because nothing was verified' do
      expect { result }.to raise_error(PG::InsufficientPrivilege)
      expect(publisher).to have_received(:close)
    end
  end

  describe 'when GEO_PUBLISHER_CONNECTION_STRING points at the wrong database' do
    using RSpec::Parameterized::TableSyntax

    where(:in_recovery, :pubviaroot, :slot_exists, :reason) do
      't' | 't' | 't' | 'it is in recovery'
      'f' | nil | 't' | 'it has no publication named geo_publication'
      'f' | 't' | 'f' | 'it has no replication slot named geo_subscription'
    end

    with_them do
      let(:target_row) { { 'in_recovery' => in_recovery, 'pubviaroot' => pubviaroot, 'slot_exists' => slot_exists } }

      it 'blocks and says why' do
        expect(result.status).to eq(:wrong_target)
        expect(result).to be_blocking
        expect(result.message).to include(reason)
      end
    end
  end

  context 'when a published relation is not in the subscription' do
    let(:published) { [%w[public projects], %w[public p_ci_builds], %w[public new_table]] }

    it 'blocks and names it' do
      expect(result.status).to eq(:uncovered_relations)
      expect(result).to be_blocking
      expect(result.message).to include('public.new_table', 'subscription:refresh')
      expect(result.message).not_to include('Create any of them')
    end

    context 'when the publication does not publish partitions through their root' do
      let(:target_row) { { 'in_recovery' => 'f', 'pubviaroot' => 'f', 'slot_exists' => 't' } }

      it 'says to create missing partitions before the refresh' do
        expect(result.message).to include('Create any of them missing on the subscriber first')
      end
    end

    context 'when many relations are missing' do
      let(:published) { (1..25).map { |i| ['public', "table_#{i.to_s.rjust(2, '0')}"] } }

      it 'lists only the first few' do
        expect(result.message).to include('public.table_20, and 5 more')
        expect(result.message).not_to include('public.table_21')
      end
    end
  end

  context 'when the subscriber catches up after a poll' do
    before do
      rows = [{ 'caught_up' => 'f', 'lag_bytes' => '1024' }, { 'caught_up' => 't', 'lag_bytes' => '0' }]

      allow(publisher).to receive(:exec_params)
        .with(described_class::SLOT_PROGRESS_SQL, anything) { pg_result([rows.shift]) }
    end

    it 'is ready' do
      expect(result.status).to eq(:ready)
      expect(publisher).to have_received(:exec_params).with(described_class::SLOT_PROGRESS_SQL, anything).twice
    end
  end

  context 'when the subscription has no stats row yet' do
    before do
      allow(subscriber).to receive(:exec_params)
        .with(described_class::ERROR_COUNT_SQL, anything).and_return(pg_result([]))
    end

    it 'is ready' do
      expect(result.status).to eq(:ready)
    end
  end

  context 'when the subscriber does not catch up in time' do
    let(:catch_up_timeout) { 0 }
    let(:progress_row) { { 'caught_up' => 'f', 'lag_bytes' => '1024' } }

    it 'blocks and reports how far behind it is' do
      expect(result.status).to eq(:lagging)
      expect(result).to be_blocking
      expect(result.message).to include('1024 bytes behind', 'GEO_REPLICATION_CHECK_TIMEOUT')
    end

    context 'when no apply worker is running' do
      let(:apply_worker_running) { 'f' }

      it 'says so' do
        expect(result.status).to eq(:apply_worker_down)
        expect(result.message).to include('no apply worker running')
      end
    end
  end

  context 'when replication errors happen during the check' do
    let(:error_counts) { [3, 4] }
    let(:progress_row) { { 'caught_up' => 'f', 'lag_bytes' => '1024' } }

    it 'blocks without waiting for the timeout' do
      expect(result.status).to eq(:apply_errors)
      expect(result).to be_blocking
      expect(publisher).not_to have_received(:exec_params).with(described_class::SLOT_PROGRESS_SQL, anything)
    end
  end

  context 'when errors only happened before the check' do
    let(:error_counts) { [3] }

    it 'is ready' do
      expect(result.status).to eq(:ready)
    end
  end

  context 'when a relation has not finished its initial copy' do
    let(:subscribed) { [%w[public projects r], %w[public p_ci_builds d]] }

    it 'blocks and names it' do
      expect(result.status).to eq(:relations_not_ready)
      expect(result).to be_blocking
      expect(result.message).to include('public.p_ci_builds')
    end
  end

  context 'when checking for writers on the publisher' do
    let(:block_on_writers) { true }

    context 'when sessions only read' do
      let(:sessions_by_call) { [[session(state: 'active')]] }

      it 'is ready, and checks before and after the first wait, then waits again' do
        expect(result.status).to eq(:ready)
        expect(publisher).to have_received(:exec_params).with(described_class::SESSIONS_SQL, []).twice
        expect(publisher).to have_received(:exec_params).with(described_class::CURRENT_LSN_SQL, []).twice
      end
    end

    context 'when a session holds a write transaction' do
      let(:sessions_by_call) { [[session(state: 'active', writes: true)]] }

      it 'blocks before waiting for the subscriber and names the session' do
        expect(result.status).to eq(:writes_detected)
        expect(result).to be_blocking
        expect(result.message).to include('pid 4242', 'Stop writes on the publisher')
        expect(publisher).not_to have_received(:exec_params).with(described_class::CURRENT_LSN_SQL, anything)
      end
    end

    context 'when a session is idle in a transaction' do
      let(:sessions_by_call) { [[session(state: 'idle in transaction')]] }

      it 'blocks' do
        expect(result.status).to eq(:writes_detected)
      end
    end

    context 'when a writer connects during the wait' do
      let(:sessions_by_call) { [[], [session(state: 'active', writes: true)]] }

      it 'blocks after the subscriber caught up' do
        expect(result.status).to eq(:writes_detected)
        expect(publisher).to have_received(:exec_params).with(described_class::SLOT_PROGRESS_SQL, anything)
      end
    end

    context 'when a commit lands between the writer checks' do
      let(:catch_up_timeout) { 0 }
      let(:progress_by_call) { [progress_row, { 'caught_up' => 'f', 'lag_bytes' => '512' }] }

      it 'blocks until the subscriber applies it' do
        expect(result.status).to eq(:lagging)
        expect(result.message).to include('512 bytes behind')
      end
    end

    context 'when the role cannot see other sessions' do
      let(:masked_sessions) { '2' }

      it 'blocks and names the missing grant' do
        expect(result.status).to eq(:stats_not_visible)
        expect(result).to be_blocking
        expect(result.message).to include('GRANT pg_read_all_stats TO gitlab_replicator')
      end
    end
  end

  context 'when not checking for writers' do
    let(:sessions_by_call) { [[session(state: 'active', writes: true)]] }

    it 'does not look at publisher sessions, and waits once' do
      expect(result.status).to eq(:ready)
      expect(publisher).to have_received(:exec_params).with(described_class::CURRENT_LSN_SQL, []).once
      expect(publisher).not_to have_received(:exec_params).with(described_class::MASKED_SESSIONS_SQL, anything)
      expect(publisher).not_to have_received(:exec_params).with(described_class::SESSIONS_SQL, anything)
    end
  end

  # Runs the real SQL against the test database, so a renamed catalog column fails here instead of
  # silently degrading a cutover in the field.
  describe 'against the test database' do
    let(:connection) { PG.connect(test_db_connection_string) }

    let(:test_db_connection_string) do
      config = ApplicationRecord.connection_db_config.configuration_hash

      PG::Connection.parse_connect_args(
        {
          host: config[:host], port: config[:port], dbname: config[:database],
          user: config[:username], password: config[:password]
        }.compact
      )
    end

    before do
      allow(PG).to receive(:connect).and_call_original
    end

    after do
      connection.close
    end

    it 'runs every catalog query' do
      lsn = connection.exec_params(described_class::CURRENT_LSN_SQL, []).first['lsn']

      expect(connection.exec_params(described_class::SUBSCRIPTION_SQL, ['geo_subscription']).values).to be_empty
      expect(connection.exec_params(described_class::ERROR_COUNT_SQL, ['0']).values).to be_empty
      expect(connection.exec_params(described_class::SUBSCRIBED_RELATIONS_SQL, ['0']).values).to be_empty
      expect(connection.exec_params(described_class::APPLY_WORKER_SQL, ['0']).first['running']).to eq('f')
      expect(connection.exec_params(described_class::PUBLISHER_TARGET_SQL, %w[geo_publication geo_subscription])
        .first).to eq('in_recovery' => 'f', 'pubviaroot' => nil, 'slot_exists' => 'f')
      expect(connection.exec_params(described_class::SLOT_PROGRESS_SQL, ['geo_subscription', lsn]).values).to be_empty
      expect(connection.exec_params(described_class::MASKED_SESSIONS_SQL, []).first).to have_key('masked_sessions')
      expect(connection.exec_params(described_class::SESSIONS_SQL, []).fields)
        .to include('pid', 'state', 'holds_write_transaction', 'transaction_age_seconds', 'query')
    end

    it 'lists a partitioned table under its root when it is published through its root' do
      connection.exec('BEGIN')
      connection.exec(<<~SQL)
        CREATE TABLE _test_geo_readiness_parent (id int NOT NULL) PARTITION BY LIST (id);
        CREATE TABLE _test_geo_readiness_leaf PARTITION OF _test_geo_readiness_parent FOR VALUES IN (1);
        CREATE PUBLICATION geo_readiness_spec FOR TABLE _test_geo_readiness_parent
          WITH (publish_via_partition_root = true);
      SQL

      relations = connection.exec_params(described_class::PUBLISHED_RELATIONS_SQL, ['geo_readiness_spec']).values

      expect(relations).to eq([%w[public _test_geo_readiness_parent]])
    ensure
      connection.exec('ROLLBACK')
    end

    it 'reports a database without the subscription' do
      result = described_class.new(
        subscriber: connection, publisher_connection_string: test_db_connection_string,
        publication_name: 'geo_publication', subscription_name: 'geo_subscription'
      ).execute

      expect(result.status).to eq(:no_subscription)
    end
  end
end
