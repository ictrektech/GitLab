# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::Code::RepositoryIndexWorker, :with_active_context_adapter_reset, feature_category: :global_search do
  let(:worker) { described_class.new }

  it_behaves_like 'active_context pause-controlled worker' do
    let(:worker_params) { [123] }
  end

  it 'has the `until_executing` deduplicate strategy including scheduled jobs' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executing)
    expect(described_class.get_deduplication_options).to include(including_scheduled: true)
  end

  describe 'deduplication of scheduled jobs', :clean_gitlab_redis_queues_metadata do
    let(:repository_id) { 123 }

    it 'drops a duplicate scheduled job for the same repository while the first is scheduled' do
      first_job = described_class.perform_in(described_class::RETRY_IN_IF_LOCKED, repository_id)
      second_job = described_class.perform_in(described_class::RETRY_IN_IF_LOCKED, repository_id)

      expect(first_job).to be_present
      expect(second_job).to be_nil
    end

    it 'drops an immediate job for the same repository while a scheduled job exists' do
      scheduled_job = described_class.perform_in(described_class::RETRY_IN_IF_LOCKED, repository_id)
      immediate_job = described_class.perform_async(repository_id)

      expect(scheduled_job).to be_present
      expect(immediate_job).to be_nil
    end

    it 'folds repeated delayed jobs for the same repository into one' do
      stub_saas_features(gitlab_com_subscriptions: true)
      repository = build_stubbed(:ai_active_context_code_repository, id: repository_id)

      first_job = described_class.perform_with_push_delay(repository)
      second_job = described_class.perform_with_push_delay(repository)

      expect(first_job).to be_present
      expect(second_job).to be_nil
    end
  end

  describe '.perform_with_push_delay' do
    let(:repository) { build_stubbed(:ai_active_context_code_repository) }

    context 'on SaaS' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'schedules the job after the push indexing delay' do
        expect(described_class).to receive(:perform_in).with(described_class::PUSH_INDEXING_DELAY, repository.id)
        expect(described_class).not_to receive(:perform_async)

        described_class.perform_with_push_delay(repository)
      end

      context 'when active_context_code_push_indexing_delay is disabled' do
        before do
          stub_feature_flags(active_context_code_push_indexing_delay: false)
        end

        it 'schedules the job without a delay' do
          expect(described_class).to receive(:perform_async).with(repository.id)
          expect(described_class).not_to receive(:perform_in)

          described_class.perform_with_push_delay(repository)
        end
      end
    end

    context 'when not on SaaS' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'schedules the job without a delay' do
        expect(described_class).to receive(:perform_async).with(repository.id)
        expect(described_class).not_to receive(:perform_in)

        described_class.perform_with_push_delay(repository)
      end
    end
  end

  describe '#perform' do
    let_it_be_with_reload(:repository) { create(:ai_active_context_code_repository, state: :pending) }

    let(:logger) { instance_double(::Gitlab::ActiveContext::Logger, info: nil) }

    before do
      allow(::ActiveContext::Config).to receive(:logger).and_return(logger)
      allow(::Ai::ActiveContext::Collections::Code).to receive(:indexing?).and_return(true)
      allow(Ai::ActiveContext::Code::InitialIndexingService).to receive(:execute)
      allow(Ai::ActiveContext::Code::IncrementalIndexingService).to receive(:execute)
    end

    context 'when ActiveContext indexing is enabled' do
      context 'with a valid pending repository' do
        before do
          repository.pending!
        end

        it 'calls InitialIndexingService.execute with the repository' do
          worker.perform(repository.id)

          expect(Ai::ActiveContext::Code::InitialIndexingService).to have_received(:execute).with(repository)
          expect(Ai::ActiveContext::Code::IncrementalIndexingService).not_to have_received(:execute).with(repository)
        end

        it 'logs the start and end of indexing' do
          expect(logger).to receive(:info).with({
            'class_name' => described_class.name,
            'message' => 'Indexing started',
            'ai_active_context_code_repository_id' => repository.id,
            'project_id' => repository.project_id,
            'enabled_namespace_id' => repository.enabled_namespace_id,
            'indexing_mode' => 'initial'
          })
          expect(logger).to receive(:info).with({
            'class_name' => described_class.name,
            'message' => 'Indexing done',
            'ai_active_context_code_repository_id' => repository.id,
            'project_id' => repository.project_id,
            'enabled_namespace_id' => repository.enabled_namespace_id,
            'indexing_mode' => 'initial'
          })

          worker.perform(repository.id)
        end
      end

      context 'with a valid pending_retry repository' do
        before do
          repository.pending_retry!
        end

        it 'calls InitialIndexingService.execute with the repository' do
          worker.perform(repository.id)

          expect(Ai::ActiveContext::Code::InitialIndexingService).to have_received(:execute).with(repository)
          expect(Ai::ActiveContext::Code::IncrementalIndexingService).not_to have_received(:execute).with(repository)
        end
      end

      context 'with a valid ready repository' do
        before do
          repository.ready!
        end

        it 'calls IncrementalIndexingService.execute' do
          worker.perform(repository.id)

          expect(Ai::ActiveContext::Code::InitialIndexingService).not_to have_received(:execute)
          expect(Ai::ActiveContext::Code::IncrementalIndexingService).to have_received(:execute).with(repository)
        end
      end

      context 'with a valid repository that is not pending, pending_retry, or ready' do
        before do
          repository.failed!
        end

        it 'does not call any indexing service' do
          expect(Ai::ActiveContext::Code::InitialIndexingService).not_to receive(:execute)
          expect(Ai::ActiveContext::Code::IncrementalIndexingService).not_to receive(:execute)

          worker.perform(repository.id)
        end
      end

      context 'with a non-existent repository' do
        it 'does not call IndexingService.execute' do
          worker.perform(999999)

          expect(Ai::ActiveContext::Code::InitialIndexingService).not_to have_received(:execute)
        end
      end
    end

    context 'when indexing is disabled' do
      before do
        allow(::Ai::ActiveContext::Collections::Code).to receive(:indexing?).and_return(false)
        repository.pending!
      end

      it 'does not call InitialIndexingService.execute' do
        worker.perform(repository.id)

        expect(Ai::ActiveContext::Code::InitialIndexingService).not_to have_received(:execute)
      end
    end

    describe 'parallel execution' do
      include ExclusiveLeaseHelpers

      let(:lease_key) { "Ai::ActiveContext::Code::RepositoryIndexWorker/#{repository.id}" }

      before do
        repository.pending!
        stub_exclusive_lease_taken(lease_key, timeout: described_class::LEASE_TTL)
      end

      context 'when the lock is locked' do
        it 'does not run service' do
          expect(worker).to receive(:in_lock)
            .with(lease_key,
              ttl: described_class::LEASE_TTL,
              retries: described_class::LEASE_RETRIES,
              sleep_sec: described_class::LEASE_TRY_AFTER)

          expect(Ai::ActiveContext::Code::InitialIndexingService).not_to receive(:execute)

          worker.perform(repository.id)
        end

        it 'schedules a new job' do
          expect(worker).to receive(:in_lock)
            .with(lease_key,
              ttl: described_class::LEASE_TTL,
              retries: described_class::LEASE_RETRIES,
              sleep_sec: described_class::LEASE_TRY_AFTER)
            .and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

          expect(described_class).to receive(:perform_in)
            .with(described_class::RETRY_IN_IF_LOCKED, repository.id)

          worker.perform(repository.id)
        end
      end
    end
  end
end
