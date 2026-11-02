# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::Code::IncrementalIndexingService, feature_category: :global_search do
  let_it_be(:collection) { create(:ai_active_context_collection) }
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:repository) do
    create(
      :ai_active_context_code_repository,
      state: :ready,
      project: project,
      metadata: { initial_indexing_last_queued_item: 'hash0' }
    )
  end

  let(:logger) { instance_double(::Gitlab::ActiveContext::Logger, info: nil, error: nil) }
  let(:previous_commit) { 'previous-commit-sha' }
  let(:indexed_commit) { 'indexed-commit-sha' }

  before do
    allow(ActiveContext::CollectionCache).to receive(:fetch).and_return(collection)
    allow(::ActiveContext::Config).to receive(:logger).and_return(logger)
  end

  def build_log_payload(message, extra_params = {})
    {
      class_name: described_class.to_s,
      message: message,
      ai_active_context_code_repository_id: repository.id,
      project_id: project.id
    }.merge(extra_params).stringify_keys
  end

  describe '.execute' do
    subject(:execute) { described_class.execute(repository) }

    it 'calls the indexer with a block and tracks refs for each id as it processes' do
      expect(repository.state).to eq('ready')

      expect(Ai::ActiveContext::Code::Indexer).to receive(:run!) do |repo, &block|
        expect(repo).to eq(repository)
        block.call('hash1')
        block.call('hash2')

        indexed_commit
      end

      expect(::Ai::ActiveContext::Collections::Code).to receive(:track_refs!)
                                                          .with(hashes: ['hash1'], routing: repository.project_id)
      expect(::Ai::ActiveContext::Collections::Code).to receive(:track_refs!)
                                                          .with(hashes: ['hash2'], routing: repository.project_id)

      expect(logger).to receive(:info).with(
        build_log_payload('incremental_indexing_last_queued_item', incremental_indexing_last_queued_item: 'hash2')
      ).ordered
      expect(logger).to receive(:info).with(build_log_payload('enqueued_refs', enqueued_refs_count: 2)).ordered

      execute

      expect(repository.state).to eq('ready')
      expect(repository.last_commit).to eq(indexed_commit)
      expect(repository.incremental_indexing_last_queued_item).to eq('hash2')
      expect(repository.initial_indexing_last_queued_item).to eq('hash0')
    end

    context 'when the indexer yields no ids' do
      before do
        allow(Ai::ActiveContext::Code::Indexer).to receive(:run!).and_return(indexed_commit)
      end

      it 'saves the indexed commit without setting incremental_indexing_last_queued_item' do
        execute

        expect(repository.last_commit).to eq(indexed_commit)
        expect(repository.incremental_indexing_last_queued_item).to be_nil
      end
    end

    context 'when the repository has a stale error from a previous failure' do
      before do
        repository.update!(last_error: 'previous failure')

        allow(Ai::ActiveContext::Code::Indexer).to receive(:run!)
      end

      it 'clears the stale error on a successful run' do
        execute

        expect(repository.last_error).to be_nil
      end
    end

    context 'when the indexer run fails' do
      let(:error) { Ai::ActiveContext::Code::IndexerBase::Error.new('Indexer failed') }

      before do
        repository.update!(last_commit: previous_commit)

        allow(Ai::ActiveContext::Code::Indexer).to receive(:run!).and_raise(error)
      end

      it 'records and tracks the error without raising, so Sidekiq does not retry' do
        expect(logger).to receive(:error).with(
          build_log_payload('incremental indexing failed', last_error: error.message)
        )

        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          error,
          ai_active_context_code_repository_id: repository.id,
          project_id: project.id
        )

        expect { execute }.not_to raise_error

        expect(repository.state).to eq('ready')
        expect(repository.last_error).to eq(error.message)
        expect(repository.last_commit).to eq(previous_commit)
      end
    end

    context 'when an unexpected error is raised' do
      let(:error) { StandardError.new('Indexing failed') }

      before do
        allow(Ai::ActiveContext::Code::Indexer).to receive(:run!).and_raise(error)
      end

      it 'records the error and passes it on for Sidekiq to retry' do
        expect(logger).to receive(:error).with(
          build_log_payload('incremental indexing failed', last_error: error.message)
        )

        expect { execute }.to raise_error(error)

        expect(repository.state).to eq('ready')
        expect(repository.last_error).to eq(error.message)
      end
    end

    context 'when the indexer is interrupted by a deploy signal' do
      before do
        repository.update!(last_error: 'previous failure')

        allow(Ai::ActiveContext::Code::Indexer).to receive(:run!)
          .and_raise(Ai::ActiveContext::Code::IndexerBase::Interrupted)
      end

      it 'leaves the repository ready without touching the existing error, but re-raises for Sidekiq to retry' do
        expect(logger).not_to receive(:error)

        expect { execute }.to raise_error(Ai::ActiveContext::Code::IndexerBase::Interrupted)

        expect(repository.state).to eq('ready')
        expect(repository.last_error).to eq('previous failure')
      end
    end
  end
end
