# frozen_string_literal: true

require 'spec_helper'

# Protects the asynchronous stop boundary: only the captured application generation may run, a retryable failed
# stop stays executable, and the cleanup is enqueued only once the cutover has committed.
RSpec.describe Import::Sync::Repositories::FinishStopWorker, feature_category: :importers do
  let(:application_generation) { 4 }
  let(:authority_state) { :cutting_over }
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: create(:project, :import_finished),
      authority_state: authority_state,
      application_generation: application_generation
    )
  end

  let(:service) { instance_double(Import::Sync::Repositories::FinishStopService, execute: true) }

  subject(:worker) { described_class.new }

  before do
    allow(Import::Sync::Repositories::FinishStopService).to receive(:new).and_return(service)
    allow(described_class).to receive(:perform_async)
    allow(Import::Sync::Repositories::StopCleanupWorker).to receive(:perform_async)
  end

  def perform
    worker.perform(repository.id, application_generation)
  end

  it 'is configured to hold its deduplication lock until the job finishes and reschedule once' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(if_deduplicated: :reschedule_once)
    expect(described_class.get_deduplication_options).not_to include(:including_scheduled)
  end

  it 'retries five times and does not go to the dead set' do
    expect(described_class.get_sidekiq_options).to include('retry' => 5, 'dead' => false)
  end

  it 'declares its external dependencies, idempotency and sticky data consistency' do
    expect(described_class).to be_worker_has_external_dependencies
    expect(described_class).to be_idempotent
    expect(described_class.get_data_consistency_per_database.values).to all(eq(:sticky))
    expect(described_class.get_feature_category).to eq(:importers)
  end

  it 'shares the GitHub import concurrency limit' do
    stub_application_setting(import_jobs_concurrency_limit: 7)

    expect(described_class.get_concurrency_limit).to eq(7)
  end

  it 'runs the final check for the captured stopping generation' do
    perform

    expect(Import::Sync::Repositories::FinishStopService)
      .to have_received(:new).with(repository, application_generation: application_generation)
    expect(service).to have_received(:execute)
  end

  it 'queues the same fenced stop after a bounded nonterminal page' do
    allow(service).to receive(:execute).and_return(false)

    perform

    expect(described_class).to have_received(:perform_async).with(repository.id, application_generation).once
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  it 'admits a retryable failed stop with the same generation' do
    repository.update!(authority_state: :cutover_failed)

    perform

    expect(service).to have_received(:execute)
  end

  it 'does not run after the application generation changes' do
    repository.update!(application_generation: application_generation + 1)

    perform

    expect(service).not_to have_received(:execute)
    expect(described_class).not_to have_received(:perform_async)
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  it 'does not run after GitLab becomes authoritative #security' do
    repository.update!(authority_state: :gitlab_canonical)

    perform

    expect(service).not_to have_received(:execute)
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  it 'does nothing when the repository is gone' do
    worker.perform(non_existing_record_id, application_generation)

    expect(Import::Sync::Repositories::FinishStopService).not_to have_received(:new)
    expect(described_class).not_to have_received(:perform_async)
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  context 'when the row is not part of this stop' do
    where(:row_attributes) do
      [
        [{ authority_state: :provisioning }],
        [{ authority_state: :bootstrap_canceled }],
        [{ authority_state: :provider_canonical }],
        [{ authority_state: :disconnected, disconnect_reason: :token_revoked,
           restore_authority_state: :provider_canonical }]
      ]
    end

    with_them do
      it 'does not run the service or enqueue anything' do
        repository.update!(row_attributes)

        perform

        expect(service).not_to have_received(:execute)
        expect(described_class).not_to have_received(:perform_async)
        expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
      end
    end
  end

  it 'enqueues StopCleanupWorker once when the service returns true' do
    perform

    expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(repository.id).once
    expect(described_class).not_to have_received(:perform_async)
  end

  it 'enqueues the cleanup only after the service has returned' do
    repository
    baseline = ApplicationRecord.connection.open_transactions
    calls = []
    allow(service).to receive(:execute) do
      calls << :service
      true
    end
    allow(Import::Sync::Repositories::StopCleanupWorker).to receive(:perform_async) do
      calls << [:cleanup, ApplicationRecord.connection.open_transactions]
    end

    perform

    expect(calls).to eq([:service, [:cleanup, baseline]])
  end

  context 'when this very stop already completed' do
    let(:authority_state) { :gitlab_canonical }
    let(:repository) do
      create(
        :import_sync_repository,
        :oauth,
        authority_state: :gitlab_canonical,
        application_generation: application_generation + 1
      )
    end

    it 'enqueues StopCleanupWorker again without running the service #security' do
      perform

      expect(Import::Sync::Repositories::FinishStopService).not_to have_received(:new)
      expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).with(repository.id).once
      expect(described_class).not_to have_received(:perform_async)
    end
  end

  context 'when GitLab is canonical at another generation' do
    where(:generation_offset) { [[2], [-1]] }

    with_them do
      it 'does not enqueue the cleanup #security' do
        repository.update!(
          authority_state: :gitlab_canonical,
          application_generation: application_generation + generation_offset
        )

        perform

        expect(service).not_to have_received(:execute)
        expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
        expect(described_class).not_to have_received(:perform_async)
      end
    end
  end

  it 'does not enqueue the cleanup when the service raises' do
    allow(service).to receive(:execute).and_raise(StandardError, 'provider failure')

    expect { perform }.to raise_error(StandardError, 'provider failure')

    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
    expect(described_class).not_to have_received(:perform_async)
  end

  it 'does not raise or enqueue anything for a stop that became stale under the lease' do
    allow(service).to receive(:execute).and_raise(Import::Sync::Repositories::FinishStopService::StaleStopError)

    expect { perform }.not_to raise_error

    expect(described_class).not_to have_received(:perform_async)
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  context 'when GitHub rate limits the final check' do
    before do
      allow(described_class).to receive(:perform_in)
    end

    it 'reschedules the same stop for the reset instead of spending retries' do
      allow(service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError.new('limited', 10.minutes))

      expect { perform }.not_to raise_error

      expect(described_class).to have_received(:perform_in).with(10.minutes, repository.id, application_generation)
      expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
    end

    it 'waits at least the minimum delay' do
      allow(service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError.new('limited', 0))

      perform

      expect(described_class).to have_received(:perform_in)
        .with(Import::Sync::Repositories::ReconcileWorker::RATE_LIMIT_MIN_DELAY, repository.id, application_generation)
    end

    it 'falls back to the default delay when GitHub gives no reset time' do
      allow(service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError)

      perform

      expect(described_class).to have_received(:perform_in).with(
        Import::Sync::Repositories::ReconcileWorker::RATE_LIMIT_FALLBACK_DELAY, repository.id, application_generation
      )
    end
  end

  it 'lets FailedToObtainLockError propagate and enqueues nothing' do
    allow(service).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    allow(described_class).to receive(:perform_in)

    expect { perform }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

    expect(described_class).not_to have_received(:perform_in)
    expect(described_class).not_to have_received(:perform_async)
    expect(Import::Sync::Repositories::StopCleanupWorker).not_to have_received(:perform_async)
  end

  context 'with the real lease and stubbed reconcile services', :clean_gitlab_redis_shared_state do
    let(:application_generation) { 6 }
    let(:source_service) do
      instance_double(Import::Sync::Repositories::ReconcileSourceService, execute: terminal_result)
    end

    let(:work_items_service) do
      instance_double(Import::Sync::Repositories::ReconcileWorkItemsService, execute: terminal_result)
    end

    let(:terminal_result) { { applied_domains: [], follow_up: false } }

    before do
      allow(Import::Sync::Repositories::FinishStopService).to receive(:new).and_call_original
      allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new).and_return(source_service)
      allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new).and_return(work_items_service)
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [repository.id, application_generation] }

      before do
        Import::Sync::RepositoryState.domains.each_key do |domain|
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

      it 'completes the stop on the first run and returns at the pre-check on the second' do
        perform_idempotent_work

        expect(repository.reload).to have_attributes(
          authority_state: 'gitlab_canonical',
          application_generation: application_generation + 1
        )
        expect(source_service).to have_received(:execute).once
        expect(work_items_service).to have_received(:execute).once
        expect(Import::Sync::Repositories::StopCleanupWorker).to have_received(:perform_async).twice
      end
    end
  end
end
