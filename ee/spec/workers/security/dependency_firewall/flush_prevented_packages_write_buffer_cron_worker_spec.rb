# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::FlushPreventedPackagesWriteBufferCronWorker,
  :clean_gitlab_redis_shared_state, :freeze_time, feature_category: :dependency_firewall do
  let_it_be(:project) { create(:project) }

  let(:ledger_model) { Security::DependencyFirewallPreventedPackage }
  let(:now) { Time.current.utc }

  subject(:worker) { described_class.new }

  def buffer_entry(
    project_id: project.id, rule_type: 'license', identifier: 'pkg:npm/a@1',
    seen_at: now, blocked: true, warned: false, severity: nil)
    ledger_model.write_buffer.add(
      project_id: project_id,
      rule_type: ledger_model.rule_types[rule_type],
      identifier: identifier,
      seen_at: seen_at,
      blocked: blocked,
      warned: warned,
      severity: severity && ledger_model.severities[severity]
    )
  end

  it_behaves_like 'an idempotent worker' do
    before do
      buffer_entry
    end

    it 'applies buffered entries exactly once across repeated runs', :aggregate_failures do
      perform_idempotent_work

      expect(ledger_model.count).to eq(1)
      expect(ledger_model.last).to have_attributes(identifier: 'pkg:npm/a@1', rule_type: 'license')
    end
  end

  it 'does nothing when the buffer is empty' do
    expect { worker.perform }.not_to change { ledger_model.count }
  end

  it 'writes a buffered entry to the ledger', :aggregate_failures do
    buffer_entry(rule_type: 'risk_severity', severity: 'high', warned: true)

    expect { worker.perform }.to change { ledger_model.count }.by(1)

    expect(ledger_model.last).to have_attributes(
      project_id: project.id,
      rule_type: 'risk_severity',
      identifier: 'pkg:npm/a@1',
      first_seen_at: be_like_time(now),
      last_blocked_at: be_like_time(now),
      last_warned_at: be_like_time(now),
      severity: 'high'
    )
  end

  it 'collapses repeat activity into one row carrying the merged timestamps', :aggregate_failures do
    buffer_entry(seen_at: now - 2.hours)
    buffer_entry(seen_at: now)

    expect { worker.perform }.to change { ledger_model.count }.by(1)
    expect(ledger_model.last).to have_attributes(
      first_seen_at: be_like_time(now - 2.hours),
      last_blocked_at: be_like_time(now)
    )
  end

  it 'merges onto an existing row from an earlier flush via GREATEST/LEAST', :aggregate_failures do
    buffer_entry(seen_at: now - 2.hours)
    worker.perform

    buffer_entry(seen_at: now)
    expect { worker.perform }.not_to change { ledger_model.count }

    expect(ledger_model.last).to have_attributes(
      first_seen_at: be_like_time(now - 2.hours),
      last_blocked_at: be_like_time(now)
    )
  end

  it 'empties the buffer so a second run is a no-op', :aggregate_failures do
    buffer_entry
    worker.perform

    expect { worker.perform }.not_to change { ledger_model.count }
    expect(ledger_model.write_buffer.staged_size).to eq(0)
  end

  it 'reports what it flushed' do
    buffer_entry(identifier: 'pkg:npm/a@1')
    buffer_entry(identifier: 'pkg:npm/b@1')

    expect(worker).to receive(:log_extra_metadata_on_done).with(:result, {
      status: :processed, flushed_entries: 2, discarded_entries: 0, remaining_entries: 0,
      buffered_entries: 0
    })

    worker.perform
  end

  it 'accumulates the tally across batches rather than reporting only the last one' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    buffer_entry(identifier: 'pkg:npm/a@1')
    buffer_entry(identifier: 'pkg:npm/b@1')

    expect(worker).to receive(:log_extra_metadata_on_done).with(:result, {
      status: :processed, flushed_entries: 2, discarded_entries: 0, remaining_entries: 0,
      buffered_entries: 0
    })

    worker.perform
  end

  it 'counts activity that arrives mid-flush on the next run rather than dropping it', :aggregate_failures do
    buffer_entry(seen_at: now - 1.hour)

    allow(ledger_model).to receive(:bulk_upsert!).and_wrap_original do |original, rows|
      buffer_entry(seen_at: now) # lands in the live buffer while the staged batch is being written
      original.call(rows)
    end

    worker.perform
    expect(ledger_model.last.last_blocked_at).to be_like_time(now - 1.hour)

    worker.perform
    expect(ledger_model.last.last_blocked_at).to be_like_time(now)
  end

  context 'when scheduling refreshes for the ancestor groups of flushed projects' do
    let(:refresh_worker) { Security::DependencyFirewall::RefreshGroupPreventedStatsWorker }
    let(:affected_groups) { Security::DependencyFirewall::PreventedStats::AffectedGroups }
    let_it_be(:other_project) { create(:project) }

    it 'resolves the unique project ids once per flushed batch', :aggregate_failures do
      buffer_entry(identifier: 'pkg:npm/a@1')
      buffer_entry(identifier: 'pkg:npm/b@1')
      buffer_entry(project_id: other_project.id, identifier: 'pkg:npm/c@1')

      expect(affected_groups).to receive(:for_projects).once.and_wrap_original do |original, project_ids|
        expect(project_ids).to contain_exactly(project.id, other_project.id)
        original.call(project_ids)
      end

      worker.perform
    end

    it 'schedules nothing when the buffer is empty' do
      expect(affected_groups).not_to receive(:for_projects)
      expect(refresh_worker).not_to receive(:schedule)

      worker.perform
    end

    it 'schedules a refresh for the ancestor groups of the flushed projects' do
      group = create(:group)
      subgroup = create(:group, parent: group)
      buffer_entry(project_id: create(:project, group: subgroup).id)

      expect(refresh_worker).to receive(:schedule).with(contain_exactly(group.id, subgroup.id))

      worker.perform
    end

    context 'when a batch carries a poison entry' do
      before do
        buffer_entry(project_id: non_existing_record_id, identifier: 'pkg:npm/gone@1')
        buffer_entry(identifier: 'pkg:npm/good@1')
        buffer_entry(project_id: other_project.id, identifier: 'pkg:npm/other@1')
      end

      it 'schedules only the committed entries, once, after the row-by-row retry', :aggregate_failures do
        expect(affected_groups).to receive(:for_projects).once.and_wrap_original do |original, project_ids|
          expect(project_ids).to contain_exactly(project.id, other_project.id)
          original.call(project_ids)
        end

        worker.perform
      end
    end

    context 'when scheduling raises' do
      let(:error) { StandardError.new('redis gone') }

      before do
        allow(refresh_worker).to receive(:schedule).and_raise(error)
      end

      it 'raises in development and specs, after the batch is written', :aggregate_failures do
        buffer_entry

        expect { worker.perform }.to raise_error(error)

        expect(ledger_model.count).to eq(1)
        expect(ledger_model.write_buffer.staged_size).to eq(0)
      end

      context 'when error tracking does not raise, as outside development' do
        before do
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)
        end

        it 'tracks the error and still flushes without re-staging', :aggregate_failures do
          buffer_entry

          expect { worker.perform }.not_to raise_error

          expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception).with(error)
          expect(ledger_model.count).to eq(1)
          expect(ledger_model.write_buffer.staged_size).to eq(0)
        end

        it 'does not change the result reported for the row-by-row retry', :aggregate_failures do
          buffer_entry
          buffer_entry(project_id: non_existing_record_id, identifier: 'pkg:npm/gone@1')

          expect(worker).to receive(:log_extra_metadata_on_done).with(:result, {
            status: :processed, flushed_entries: 1, discarded_entries: 1, remaining_entries: 0,
            buffered_entries: 0
          })

          worker.perform

          expect(Gitlab::ErrorTracking).to have_received(:track_and_raise_for_dev_exception).once
        end
      end
    end
  end

  context 'when the database write fails' do
    before do
      allow(ledger_model).to receive(:bulk_upsert!).and_raise(ActiveRecord::ConnectionTimeoutError, 'boom')
    end

    it 'raises so Sidekiq retries' do
      buffer_entry

      expect { worker.perform }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    end

    it 'keeps the entries staged so a later run applies them exactly once', :aggregate_failures do
      buffer_entry

      expect { worker.perform }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      expect(ledger_model.count).to eq(0)

      allow(ledger_model).to receive(:bulk_upsert!).and_call_original
      worker.perform

      expect(ledger_model.count).to eq(1)
    end
  end

  context 'when the database write fails transiently' do
    using RSpec::Parameterized::TableSyntax

    where(:error_class) do
      [
        ActiveRecord::QueryCanceled,
        ActiveRecord::ConnectionFailed,
        ActiveRecord::Deadlocked
      ]
    end

    with_them do
      before do
        allow(ledger_model).to receive(:bulk_upsert!).and_raise(error_class, 'transient')
      end

      it 'raises so Sidekiq retries, discarding nothing', :aggregate_failures do
        buffer_entry

        expect(worker.logger).not_to receive(:warn)
        expect { worker.perform }.to raise_error(error_class)
        expect(ledger_model.write_buffer.staged_size).to eq(1)
      end
    end
  end

  context 'when a page of staged entries is larger than a batch' do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      # A small hash comes back from HSCAN in one page whatever COUNT says.
      5.times { |i| buffer_entry(identifier: "pkg:npm/a@#{i}") }
    end

    it 'still upserts at most BATCH_SIZE rows per statement and writes everything', :aggregate_failures do
      sizes = []
      allow(ledger_model).to receive(:bulk_upsert!).and_wrap_original do |original, rows|
        sizes << rows.size
        original.call(rows)
      end

      worker.perform

      expect(sizes).to all(be <= 2)
      expect(ledger_model.count).to eq(5)
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when clearing the staged entries' do
    # A COMMIT that fails after the entries were cleared would lose the batch.
    def transaction_depths_at_clear
      baseline = ledger_model.connection.open_transactions
      depths = []

      # write_buffer is memoized on the model, so stub the instance the worker will actually use.
      allow(ledger_model.write_buffer).to receive(:remove_staged).and_wrap_original do |original, entries|
        depths << (ledger_model.connection.open_transactions - baseline)
        original.call(entries)
      end

      worker.perform

      depths
    end

    it 'clears them only after the write has committed', :aggregate_failures do
      buffer_entry

      depths = transaction_depths_at_clear

      expect(depths).not_to be_empty
      expect(depths).to all(eq(0))
    end

    it 'clears them only after each write has committed in the row-by-row retry', :aggregate_failures do
      buffer_entry
      buffer_entry(project_id: non_existing_record_id, identifier: 'pkg:npm/gone@1')

      depths = transaction_depths_at_clear

      expect(depths.size).to eq(2)
      expect(depths).to all(eq(0))
    end
  end

  context 'when clearing the staged entries fails' do
    it 'keeps the committed write and the entries staged, and a rerun changes nothing', :aggregate_failures do
      buffer_entry

      allow(ledger_model.write_buffer).to receive(:remove_staged).and_raise(Redis::ConnectionError, 'redis gone')

      expect { worker.perform }.to raise_error(Redis::ConnectionError)
      expect(ledger_model.count).to eq(1)
      expect(ledger_model.write_buffer.staged_size).to eq(1)

      allow(ledger_model.write_buffer).to receive(:remove_staged).and_call_original

      expect { described_class.new.perform }
        .not_to change { ledger_model.last.attributes.except('updated_at') }
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when a buffered project no longer exists' do
    it 'discards the orphaned entry and still writes the rest', :aggregate_failures do
      buffer_entry
      buffer_entry(project_id: non_existing_record_id, identifier: 'pkg:npm/gone@1')

      expect { worker.perform }.not_to raise_error

      expect(ledger_model.where(project_id: project.id).count).to eq(1)
      expect(ledger_model.where(project_id: non_existing_record_id)).to be_empty
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when a batch carries a poison entry that violates a constraint' do
    before do
      # severity on a license row violates check_dep_fw_prevented_packages_severity_rule_type;
      # the write buffer has no DB knowledge so it stages the entry anyway.
      buffer_entry(rule_type: 'license', identifier: 'pkg:npm/poison@1', severity: 'high')
      buffer_entry(identifier: 'pkg:npm/good@1')
    end

    it 'discards the poison entry and writes the rest, with nothing left staged', :aggregate_failures do
      expect { worker.perform }.not_to raise_error

      expect(ledger_model.pluck(:identifier)).to contain_exactly('pkg:npm/good@1')
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end

    it 'reports the discarded entry, which is the signal that data is being dropped' do
      expect(worker).to receive(:log_extra_metadata_on_done).with(:result, {
        status: :processed, flushed_entries: 1, discarded_entries: 1, remaining_entries: 0,
        buffered_entries: 0
      })

      worker.perform
    end

    it 'logs the discarded entry with its identity so a reported mismatch can be traced' do
      warned = []
      allow(worker.logger).to receive(:warn) { |payload| warned << payload }

      worker.perform

      expect(warned).to contain_exactly(
        hash_including(
          'message' => 'Discarded prevented-package ledger entry that cannot be persisted',
          'project_id' => project.id,
          'rule_type' => ledger_model.rule_types['license']
        )
      )
    end
  end

  context 'when a batch carries a rule type this version does not map' do
    before do
      # As buffered by a newer node during a mixed-version deploy, or before a rollback.
      ledger_model.write_buffer.add(
        project_id: project.id, rule_type: 99, identifier: 'pkg:npm/unmapped@1',
        seen_at: now, blocked: true, warned: false, severity: nil
      )
      buffer_entry(identifier: 'pkg:npm/good@1')
    end

    it 'discards the unmapped entry and writes the rest, with nothing left staged', :aggregate_failures do
      expect { worker.perform }.not_to raise_error

      expect(ledger_model.pluck(:identifier)).to contain_exactly('pkg:npm/good@1')
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when the write raises an ArgumentError that is not an unmapped enum value' do
    before do
      allow(ledger_model).to receive(:bulk_upsert!).and_raise(ArgumentError, 'bug')
    end

    it 're-raises and keeps the entries staged instead of discarding them', :aggregate_failures do
      buffer_entry

      expect(worker.logger).not_to receive(:warn)
      expect { worker.perform }.to raise_error(ArgumentError, 'bug')
      expect(ledger_model.write_buffer.staged_size).to eq(1)
    end
  end

  context 'when a transient error hits during the row-by-row retry' do
    before do
      allow(ledger_model).to receive(:bulk_upsert!).and_invoke(
        ->(_rows) { raise ActiveRecord::InvalidForeignKey, 'batch' },
        ->(_rows) { raise ActiveRecord::QueryCanceled, 'transient' }
      )
    end

    it 're-raises and keeps the entries staged instead of discarding them', :aggregate_failures do
      buffer_entry(identifier: 'pkg:npm/a@1')
      buffer_entry(identifier: 'pkg:npm/b@1')

      expect(worker.logger).not_to receive(:warn)
      expect { worker.perform }.to raise_error(ActiveRecord::QueryCanceled)
      expect(ledger_model.write_buffer.staged_size).to eq(2)
    end
  end

  context 'when a transient error hits after the row-by-row retry committed an entry' do
    let(:affected_groups) { Security::DependencyFirewall::PreventedStats::AffectedGroups }
    let_it_be(:other_project) { create(:project) }

    before do
      calls = 0
      allow(ledger_model).to receive(:bulk_upsert!).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise ActiveRecord::InvalidForeignKey, 'batch' if calls == 1
        raise ActiveRecord::QueryCanceled, 'transient' if calls == 3

        original.call(*args, **kwargs)
      end
    end

    it 'schedules the committed entry, re-raises, and keeps the other entry staged', :aggregate_failures do
      buffer_entry(identifier: 'pkg:npm/a@1')
      buffer_entry(project_id: other_project.id, identifier: 'pkg:npm/b@1')

      scheduled_project_ids = nil
      expect(affected_groups).to receive(:for_projects).once do |ids|
        scheduled_project_ids = ids
        []
      end

      expect { worker.perform }.to raise_error(ActiveRecord::QueryCanceled)

      expect(scheduled_project_ids).to eq(ledger_model.pluck(:project_id))
      expect(ledger_model.write_buffer.staged_size).to eq(1)
    end
  end

  context 'when the staged entries span more than one page' do
    it 'follows the cursor to the next page and flushes every entry', :aggregate_failures do
      buffer_entry(identifier: 'pkg:npm/a@1')
      buffer_entry(identifier: 'pkg:npm/b@1')

      cursors = []
      # A small hash comes back from HSCAN in one page, so split it into two to exercise the cursor.
      allow(ledger_model.write_buffer).to receive(:staged_batch).and_wrap_original do |original, limit, cursor|
        cursors << cursor
        entries, = original.call(limit, '0')
        cursor == '0' ? [entries.first(1), '17'] : [entries, '0']
      end

      worker.perform

      expect(cursors).to eq(%w[0 17])
      expect(ledger_model.pluck(:identifier)).to contain_exactly('pkg:npm/a@1', 'pkg:npm/b@1')
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when the runtime limit is hit during the row-by-row retry' do
    it 'stops between rows and leaves the rest staged for the next run', :aggregate_failures do
      # The dead reference fails the batch, forcing the row-by-row path.
      buffer_entry(project_id: non_existing_record_id, identifier: 'pkg:npm/gone@1')
      buffer_entry(identifier: 'pkg:npm/a@1')
      buffer_entry(identifier: 'pkg:npm/b@1')

      row_attempts = 0
      allow(ledger_model).to receive(:bulk_upsert!).and_wrap_original do |original, rows|
        row_attempts += 1 if rows.size == 1
        original.call(rows)
      end

      # Over time once the first row has been tried, so the second row must not be.
      limited = true
      allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
        allow(limiter).to receive(:over_time?) { limited && row_attempts >= 1 }
        allow(limiter).to receive(:was_over_time?) { limited && row_attempts >= 1 }
      end

      worker.perform

      expect(row_attempts).to eq(1)
      expect(ledger_model.write_buffer.staged_size).to eq(2)

      limited = false
      described_class.new.perform

      expect(ledger_model.pluck(:identifier)).to contain_exactly('pkg:npm/a@1', 'pkg:npm/b@1')
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when the runtime limit is hit between slices of a page' do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      # A small hash comes back from HSCAN as one page, which the worker slices into 2, 2 and 1.
      5.times { |i| buffer_entry(identifier: "pkg:npm/slice-#{i}@1") }
    end

    it 'stops before the next slice and leaves the rest staged for the next run', :aggregate_failures do
      batch_upserts = 0
      allow(ledger_model).to receive(:bulk_upsert!).and_wrap_original do |original, rows|
        batch_upserts += 1
        original.call(rows)
      end

      limited = true
      allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
        allow(limiter).to receive(:over_time?) { limited && batch_upserts >= 1 }
        allow(limiter).to receive(:was_over_time?) { limited && batch_upserts >= 1 }
      end

      worker.perform

      expect(ledger_model.count).to eq(2)
      expect(ledger_model.write_buffer.staged_size).to eq(3)

      limited = false
      described_class.new.perform

      expect(ledger_model.count).to eq(5)
      expect(ledger_model.write_buffer.staged_size).to eq(0)
    end
  end

  context 'when another flush already holds the lease' do
    it 'defers, reporting the real staged backlog rather than a zero', :aggregate_failures do
      buffer_entry(identifier: 'pkg:npm/a@1')
      ledger_model.write_buffer.stage! # as if the lease holder staged and has not finished

      buffer_entry(identifier: 'pkg:npm/b@1') # left live, not staged

      allow(worker).to receive(:in_lock).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      expect(worker).to receive(:log_extra_metadata_on_done).with(:result, {
        status: :lease_taken, flushed_entries: 0, discarded_entries: 0, remaining_entries: 1,
        buffered_entries: 1
      })

      expect { worker.perform }.not_to raise_error
      expect(ledger_model.count).to eq(0)
    end
  end
end
