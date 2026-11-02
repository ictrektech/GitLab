# frozen_string_literal: true

require 'spec_helper'

# Needs real database sessions, so it cannot use let_it_be or before_all (see the :delete guard in spec_helper).
# The lease is replaced by a plain object that always succeeds, which models a lost lease: only the row lock
# is left to serialize the two completion writes.
RSpec.describe Import::Sync::Repositories::FinishStopService, :delete, feature_category: :importers do
  include ConcurrentHelpers

  let(:application_generation) { 6 }
  let(:time_a) { Time.zone.parse('2026-08-25 15:03:00') }
  let(:time_b) { Time.zone.parse('2026-08-25 15:04:00') }
  let(:requested_at) { Time.zone.parse('2026-08-25 15:00:00') }

  let!(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: create(:project, :import_finished),
      authority_state: :cutting_over,
      application_generation: application_generation,
      cutover_requested_at: requested_at
    )
  end

  let!(:domain_states) do
    Import::Sync::RepositoryState.domains.keys.map do |domain|
      create(
        :import_sync_repository_state,
        repository: repository,
        domain: domain,
        desired_generation: 1,
        synced_generation: 1,
        state: :current
      )
    end
  end

  let!(:repo_a) { Import::Sync::Repository.find(repository.id) }
  let!(:repo_b) { Import::Sync::Repository.find(repository.id) }
  let(:service_a) do
    described_class.new(repo_a, application_generation: application_generation, now: -> { time_a })
  end

  let(:service_b) do
    described_class.new(repo_b, application_generation: application_generation, now: -> { time_b })
  end

  # Eager: RSpec memoization is not thread-safe, and the worker threads are the first readers.
  let!(:events) { Concurrent::Array.new }
  let!(:waits) { Concurrent::Map.new }
  let!(:results) { Concurrent::Map.new }
  let!(:blocked_by_a) { Concurrent::Array.new }
  let!(:barrier) { Concurrent::CyclicBarrier.new(2) }
  let!(:a_in_lock) { Concurrent::Event.new }

  before do
    stub_lease
    stub_reconcile_services
    stub_wait_inside_a_lock
  end

  it 'completes once when two jobs race on the completion write #security', :aggregate_failures do
    run_parallel([job(:a, service_a), job(:b, service_b)], max_concurrency: 2)

    expect(results[:a]).to eq([:ok, true])
    expect(results[:b]).to eq([:error, described_class::StaleStopError])
    expect(waits.keys.index_with { |key| waits[key] }).to eq(
      [:a, :barrier] => true,
      [:b, :barrier] => true,
      [:b, :a_in_lock] => true
    )
    expect(blocked_by_a).to contain_exactly(be >= 1)
    [:a, :b].each do |name|
      expect(events.count([name, :source])).to eq(1)
      expect(events.count([name, :work_items])).to eq(1)
    end
    expect(Import::Sync::Repository.find(repository.id)).to have_attributes(
      authority_state: 'gitlab_canonical',
      application_generation: application_generation + 1,
      cutover_completed_at: time_a,
      cutover_requested_at: requested_at
    )
  end

  def job(name, service)
    -> do
      Thread.current[:finish_stop_job] = name
      results[name] = [:ok, service.execute]
    rescue StandardError => e
      results[name] = [:error, e.class]
    end
  end

  def stub_lease
    recorded = events
    context = Object.new
    context.define_singleton_method(:verify_repository!) do |_repository_id|
      recorded << [Thread.current[:finish_stop_job], :verify_repository!]
      true
    end
    context.define_singleton_method(:renew!) do
      recorded << [Thread.current[:finish_stop_job], :renew!]
      true
    end

    lease = Object.new
    lease.define_singleton_method(:execute) { |&block| block.call(context) }

    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).with(repository.id).and_return(lease)
  end

  def stub_reconcile_services
    source_a = reconcile_object(:a, :source)
    source_b = reconcile_object(:b, :source)
    work_items_a = reconcile_object(:a, :work_items) { wait_for_barrier(:a) }
    work_items_b = reconcile_object(:b, :work_items) do
      wait_for_barrier(:b)
      wait_for_a_in_lock
    end

    allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new) do |repo, **_options|
      repo.equal?(repo_a) ? source_a : source_b
    end

    allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new) do |repo, **_options|
      repo.equal?(repo_a) ? work_items_a : work_items_b
    end
  end

  # A reaches the completion lock only after both jobs passed every pre-check. B is held back until A is
  # inside the lock, and A is held inside the lock until B is blocked behind it.
  def stub_wait_inside_a_lock
    allow(repo_a).to receive(:sync_states_for_update).and_wrap_original do |original, *args|
      a_in_lock.set
      blocked_by_a << wait_until_a_blocks_another_backend
      original.call(*args)
    end
  end

  def reconcile_object(name, event, &after_record)
    recorded = events
    Object.new.tap do |object|
      object.define_singleton_method(:execute) do |**_options|
        recorded << [name, event]
        after_record&.call
        { applied_domains: [], follow_up: false }
      end
    end
  end

  def wait_for_barrier(name)
    waits[[name, :barrier]] = barrier.wait(10)
    raise 'barrier timed out' unless waits[[name, :barrier]]
  end

  def wait_for_a_in_lock
    waits[[:b, :a_in_lock]] = a_in_lock.wait(10)
    raise 'A never took the lock' unless waits[[:b, :a_in_lock]]
  end

  def wait_until_a_blocks_another_backend
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    sql = 'SELECT count(*) FROM pg_stat_activity WHERE pg_backend_pid() = ANY(pg_blocking_pids(pid))'

    loop do
      blocked = Import::Sync::Repository.connection.select_value(sql).to_i
      return blocked if blocked >= 1
      raise 'B never blocked on the lock' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end
end
