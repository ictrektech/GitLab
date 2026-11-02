# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Audit::CloseIdleSessionsService, :clean_gitlab_redis_shared_state,
  feature_category: :audit_events do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }

  let(:open_key) { Mcp::Audit::ResolveSessionService::OPEN_SESSIONS_KEY }

  subject(:service) { described_class.new }

  def create_session(status: :running, source: :mcp, session_started_at: Time.current)
    create(:ai_governance_session, :external,
      user: user, namespace: group, project_id: nil,
      source: source, status: status, session_started_at: session_started_at)
  end

  def mark_open(session, expires_at:)
    Gitlab::Redis::SharedState.with { |redis| redis.zadd(open_key, expires_at.to_i, session.id) }
  end

  def tracked_count
    Gitlab::Redis::SharedState.with { |redis| redis.zcard(open_key) }
  end

  before do
    allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)
  end

  describe '#execute' do
    it 'finishes a session whose window has lapsed and emits a session ended event' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)

      service.execute

      expect(session.reload).to have_attributes(status: 'finished', session_finished_at: be_present)
      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async) do |events|
        expect(events.first['event_name']).to eq('ai_agent_session_ended')
      end
    end

    # The sweep runs on a cron, so its own clock can be minutes past the moment
    # the window actually lapsed.
    it 'records the lapsed window as the finish time, not the time of the sweep' do
      session = create_session
      lapsed_at = 7.minutes.ago
      mark_open(session, expires_at: lapsed_at)

      service.execute

      expect(session.reload.session_finished_at).to be_within(1.second).of(lapsed_at)
    end

    it 'caps a stale session at the longest a window can live' do
      started_at = 3.hours.ago
      session = create_session(session_started_at: started_at)

      service.execute

      expected = started_at + Mcp::Audit::ResolveSessionService::MAX_DURATION
      expect(session.reload.session_finished_at).to be_within(1.second).of(expected)
    end

    it 'enqueues one job for the whole batch' do
      sessions = Array.new(3) { create_session }
      sessions.each { |session| mark_open(session, expires_at: 1.minute.ago) }

      service.execute

      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async).once
      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async) do |events|
        expect(events.size).to eq(3)
      end
    end

    it 'untracks the whole batch with a single command' do
      sessions = Array.new(3) { create_session }
      sessions.each { |session| mark_open(session, expires_at: 1.minute.ago) }

      recorder = RedisCommands::Recorder.new { service.execute }

      expect(recorder.by_command('zrem').count).to eq(1)
      expect(tracked_count).to eq(0)
    end

    # Finishing first means a failed enqueue loses the event. That is preferred to
    # retrying, because a re-emitted session_ended carries a fresh cloud_event_id
    # that no destination can dedupe.
    it 'keeps the session finished when the events cannot be enqueued' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)
      allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker)
        .to receive(:perform_async).and_raise(Redis::CannotConnectError)

      expect { service.execute }.to raise_error(Redis::CannotConnectError)

      expect(session.reload.status).to eq('finished')

      # The entry outlives the failure because untracking runs last. It is pruned
      # as a dead id on the next run, since the row is no longer running.
      described_class.new.execute
      expect(tracked_count).to eq(0)
    end

    it 'leaves a session whose window is still open' do
      session = create_session
      mark_open(session, expires_at: 5.minutes.from_now)

      service.execute

      expect(session.reload.status).to eq('running')
    end

    # Guards against a Redis flush leaving sessions running for ever.
    it 'finishes a stale running session that is no longer tracked in Redis' do
      session = create_session(session_started_at: (described_class::STALE_AFTER + 1.minute).ago)

      service.execute

      expect(session.reload.status).to eq('finished')
    end

    it 'ignores sessions from other sources' do
      session = create_session(source: :claude_code_glab,
        session_started_at: (described_class::STALE_AFTER + 1.minute).ago)

      service.execute

      expect(session.reload.status).to eq('running')
    end

    it 'is idempotent when a session is already finished' do
      session = create_session(status: :finished)
      mark_open(session, expires_at: 1.minute.ago)

      expect { service.execute }.not_to change { session.reload.status }
      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to have_received(:perform_async)
    end

    # A tool call can extend the window between the range read and the close.
    # Finishing the session anyway would send the next call's events to a
    # finished session, because that call still resumes it from its Redis key.
    context 'when a tool call extends the window before the sweep closes it' do
      it 'leaves the session running and still tracked' do
        session = create_session
        mark_open(session, expires_at: 1.minute.ago)

        allow(service).to receive(:extended_since?).and_return(true)

        service.execute

        expect(session.reload.status).to eq('running')
        expect(tracked_count).to eq(1)
      end
    end

    # The write is one statement, so a batch cannot half-complete and leave rows
    # finished that no later run can find.
    context 'when the write fails' do
      it 'leaves the whole batch running and emits nothing' do
        sessions = Array.new(3) { create_session }
        sessions.each { |session| mark_open(session, expires_at: 1.minute.ago) }

        allow(service).to receive(:bulk_finish).and_raise(ActiveRecord::StatementInvalid, 'boom')

        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)

        expect(sessions.map { |session| session.reload.status }).to all(eq('running'))
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to have_received(:perform_async)
        expect(tracked_count).to eq(3)
      end

      it 'closes the batch on the next run' do
        session = create_session
        mark_open(session, expires_at: 1.minute.ago)

        allow(service).to receive(:bulk_finish).and_raise(ActiveRecord::StatementInvalid, 'boom')
        expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)

        described_class.new.execute

        expect(session.reload.status).to eq('finished')
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async).once
      end
    end

    it 'finishes the batch before enqueuing its events' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)

      status_at_enqueue = nil
      allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async) do
        status_at_enqueue = session.reload.status
      end

      service.execute

      expect(status_at_enqueue).to eq('finished')
    end

    # A save bumps it automatically; the bulk write has to set it explicitly, and
    # the artifact export surfaces it alongside session_finished_at.
    it 'bumps updated_at on the closed session' do
      session = create_session
      session.update_column(:updated_at, 2.hours.ago)
      mark_open(session, expires_at: 1.minute.ago)

      expect { service.execute }.to change { session.reload.updated_at }
    end

    # The bulk write bypasses the model, so the loaded rows would otherwise still
    # read as running when the event is built from them.
    it 'leaves the closed session matching the database' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)

      emitted = nil
      allow(::Mcp::Audit::CaptureEventService).to receive(:new).and_wrap_original do |method, **kwargs|
        emitted = kwargs[:session]
        method.call(**kwargs)
      end

      service.execute

      expect(emitted).to have_attributes(status: 'finished', session_finished_at: be_present)
      expect(emitted.changed?).to be(false)
    end

    # A run deferred by the database health check can overlap the next one, and both
    # read the same running rows. Only the run that finished a row may report it.
    context 'when an overlapping run finishes a session first' do
      it 'emits nothing for it and still untracks it' do
        session = create_session
        mark_open(session, expires_at: 1.minute.ago)

        allow(::Ai::Governance::Session).to receive(:finish_running!).and_wrap_original do |method, *args, **kwargs|
          session.update_column(:status, ::Ai::Governance::Session.statuses[:finished])
          method.call(*args, **kwargs)
        end

        service.execute

        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to have_received(:perform_async)
        expect(tracked_count).to eq(0)
      end
    end

    # A lost ZREM is repaired by the dead-id prune; a lost enqueue is not, so the
    # events go out first and the leftover entry is cleaned up on the next run.
    it 'enqueues the events before untracking the batch' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)
      allow(service).to receive(:untrack_ids).and_raise(Redis::CannotConnectError)

      expect { service.execute }.to raise_error(Redis::CannotConnectError)

      expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async).once
      expect(session.reload.status).to eq('finished')
    end

    # user is optional on the model, so a deleted account leaves the session
    # closable but with nobody to attribute the event to.
    context 'when the session user has been deleted' do
      it 'finishes the session without emitting an event' do
        session = create_session
        mark_open(session, expires_at: 1.minute.ago)
        session.user.delete

        service.execute

        expect(session.reload.status).to eq('finished')
        expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).not_to have_received(:perform_async)
      end
    end

    it 'removes a stale open-set entry whose session row no longer exists' do
      session = create_session
      mark_open(session, expires_at: 1.minute.ago)
      session.destroy!

      expect { service.execute }.not_to raise_error

      expect(tracked_count).to eq(0)
    end

    it 'does nothing when there is nothing to close' do
      expect { service.execute }.not_to raise_error
    end

    # zrangebyscore and stale_since both read the oldest sessions first, so a
    # pass that stopped at one batch would never catch up once it fell behind.
    context 'when there is more than a batch to close' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
      end

      it 'keeps taking lapsed batches until the set is empty' do
        sessions = Array.new(3) { create_session }
        sessions.each { |session| mark_open(session, expires_at: 1.minute.ago) }

        service.execute

        expect(sessions.map { |session| session.reload.status }).to all(eq('finished'))
        expect(tracked_count).to eq(0)
      end

      it 'closes the oldest stale sessions first' do
        newer = create_session(session_started_at: (described_class::STALE_AFTER + 1.minute).ago)
        older = create_session(session_started_at: (described_class::STALE_AFTER + 1.hour).ago)

        closed = []
        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async) do |events|
          closed.concat(events.map { |event| event['ai_governance_session_id'] })
        end

        service.execute

        expect(closed).to eq([older.id, newer.id])
      end

      it 'keeps taking stale batches until none are left' do
        sessions = Array.new(3) do
          create_session(session_started_at: (described_class::STALE_AFTER + 1.minute).ago)
        end

        service.execute

        expect(sessions.map { |session| session.reload.status }).to all(eq('finished'))
      end

      # Every entry a batch leaves behind keeps the lowest scores, so reading
      # again would only return the same ids.
      it 'stops when a full batch resolves nothing' do
        session = create_session
        mark_open(session, expires_at: 1.minute.ago)

        allow(service).to receive(:extended_since?).and_return(true)

        recorder = RedisCommands::Recorder.new { service.execute }

        expect(recorder.by_command('zrangebyscore').count).to eq(1)
        expect(session.reload.status).to eq('running')
      end

      it 'stops after the current batch once it is over time' do
        sessions = Array.new(3) { create_session }
        sessions.each { |session| mark_open(session, expires_at: 1.minute.ago) }

        allow_next_instance_of(::Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end

        service.execute

        expect(tracked_count).to eq(2)
      end
    end
  end
end
