# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ai::ActiveContext integration', :clean_gitlab_redis_shared_state, :sidekiq_inline,
  feature_category: :global_search do
  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:project) { create(:project, group: root_namespace) }

  let_it_be_with_reload(:collection) do
    create(:ai_active_context_collection, :code_collection).tap do |c|
      c.update_metadata!(current_indexing_embedding_model: {
        model_ref: 'text_embedding_005_vertex', field: 'test_field_123'
      })
    end
  end

  let(:shard) { 0 }
  let(:routing) { project.id }
  let(:embeddings_llm_class) { ::Gitlab::Llm::Embeddings::CodeEmbeddings }
  let(:mock_embeddings_llm) { instance_double(embeddings_llm_class, :execute) }
  let(:bulk_processor) { instance_double(ActiveContext::BulkProcessor) }
  let(:identifier_success) { 'hash_success' }
  let(:identifier_fail) { 'hash_fail' }

  let(:successful_ref) do
    Ai::ActiveContext::References::Code.serialize(
      collection_id: collection.id,
      routing: routing,
      data: { id: identifier_success }
    )
  end

  let(:failing_ref) do
    Ai::ActiveContext::References::Code.serialize(
      collection_id: collection.id,
      routing: routing,
      data: { id: identifier_fail }
    )
  end

  before do
    allow(::ActiveContext).to receive_message_chain(:adapter, :full_collection_name)
      .and_return(ActiveContextHelpers.code_collection_name)
    allow(ActiveContext).to receive(:indexing?).and_return(true)
    allow(ActiveContext::Config).to receive(:re_enqueue_indexing_workers?).and_return(false)
    allow(::Ai::ActiveContext).to receive(:paused?).and_return(false)
    allow(::Ai::ActiveContext::Collections::Code).to receive(:search).and_return([])

    allow(embeddings_llm_class).to receive(:new).and_return(mock_embeddings_llm)
    allow(mock_embeddings_llm).to receive(:execute).and_return([[1, 2, 3]])
    allow(ActiveContext::BulkProcessor).to receive(:new).and_return(bulk_processor)
    allow(bulk_processor).to receive(:process)
    allow(bulk_processor).to receive(:flush).and_return([])

    clear_all_queue_tracking!
  end

  after do
    ActiveContext::CollectionCache.reset
  end

  def clear_all_queue_tracking!
    Ai::ActiveContext::Queues::Code.clear_tracking!
    ActiveContext::Queues.retry_chain.each(&:clear_tracking!)
    ActiveContext::DeadQueue.clear_tracking!
    ActiveContext::CollectionCache.reset
  end

  shared_examples 'successful processing' do
    it 'processes code refs from the queue successfully' do
      search_response = [{ 'id' => identifier_success, 'content' => 'test content' }]
      allow(::ActiveContext).to receive_message_chain(:adapter, :search).and_return(search_response)

      expect(embeddings_llm_class).to receive(:new).with(
        ['test content'],
        hash_including(
          user: nil,
          root_namespace_id: embeddings_request_root_namespace_id
        )
      )

      Ai::ActiveContext::Queues::Code.push([successful_ref])

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(1)
      expect(ActiveContext::RetryQueue.queue_size).to eq(0)
      expect(ActiveContext::DeadQueue.queue_size).to eq(0)

      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(0)
      expect(ActiveContext::RetryQueue.queue_size).to eq(0)
      expect(ActiveContext::DeadQueue.queue_size).to eq(0)
    end
  end

  shared_examples 'failure and retry flow' do
    it 'moves failed refs through the retry chain, then to the dead queue' do
      Ai::ActiveContext::Queues::Code.push([failing_ref])

      allow(::ActiveContext).to receive_message_chain(:adapter, :search)
        .and_return([{ 'id' => identifier_fail, 'content' => 'test content' }])

      allow(mock_embeddings_llm).to receive(:execute).and_raise(StandardError, 'Embeddings generation failed')
      expect(embeddings_llm_class).to receive(:new).with(
        ['test content'],
        hash_including(
          user: nil,
          root_namespace_id: embeddings_request_root_namespace_id
        )
      )

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(1)
      expect(ActiveContext::DeadQueue.queue_size).to eq(0)

      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(0)
      expect(ActiveContext::RetryQueue.queue_size).to eq(1)

      start_time = Time.current
      elapsed = 0

      ActiveContext::Queues.retry_chain.each do |stage|
        expect(stage.queue_size).to eq(1)

        # The item is not due yet, so this pass picks up nothing.
        Ai::ActiveContext::BulkProcessWorker.perform_async(stage.to_s, shard)
        expect(stage.queue_size).to eq(1)

        elapsed += stage.processing_delay + 1.second

        travel_to(start_time + elapsed) do
          Ai::ActiveContext::BulkProcessWorker.perform_async(stage.to_s, shard)

          expect(stage.queue_size).to eq(0)
          expect(stage.failure_queue.queue_size).to eq(1)
        end
      end

      expect(ActiveContext::DeadQueue.queue_size).to eq(1)
    end
  end

  shared_examples 'dead queue is not processed' do
    it 'does not process items from the dead queue' do
      ActiveContext::DeadQueue.push([failing_ref])

      expect(ActiveContext::DeadQueue.queue_size).to eq(1)

      Ai::ActiveContext::BulkProcessWorker.perform_async

      expect(ActiveContext::DeadQueue.queue_size).to eq(1)
    end

    it 'dead queue is not included in raw_queues' do
      raw_queues = ActiveContext.raw_queues

      expect(raw_queues.map(&:class)).not_to include(ActiveContext::DeadQueue)
      expect(raw_queues.map(&:class)).to include(*ActiveContext::Queues.retry_chain)
    end
  end

  shared_examples 'multiple failures and successes' do
    it 'handles mixed success and failure scenarios correctly' do
      Ai::ActiveContext::Queues::Code.push([successful_ref, failing_ref])

      # Only return content for the successful ref to simulate missing content failure
      search_response = [
        { 'id' => identifier_success, 'content' => 'success content' }
      ]
      allow(::ActiveContext).to receive_message_chain(:adapter, :search).and_return(search_response)

      expect(embeddings_llm_class).to receive(:new).with(
        ['success content'],
        hash_including(
          user: nil,
          root_namespace_id: embeddings_request_root_namespace_id
        )
      )

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(2)

      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(0)
      expect(ActiveContext::RetryQueue.queue_size).to eq(1)
      expect(ActiveContext::DeadQueue.queue_size).to eq(0)

      travel(ActiveContext::RetryQueue.processing_delay + 1.second) do
        # On the retry pass, ContentNotFoundError is treated as a skip (not retried to dead queue)
        expect(::ActiveContext::Logger).to receive(:exception).with(anything, hash_including(handling: :skipped))
        Ai::ActiveContext::BulkProcessWorker.perform_async('ActiveContext::RetryQueue', shard)

        expect(ActiveContext::RetryQueue.queue_size).to eq(0)
        expect(ActiveContext::DeadQueue.queue_size).to eq(0)
      end
    end
  end

  shared_examples 'RetryQueue requests both models during a migration' do
    it 'requests embeddings for both the current and next model when processing a retried ref' do
      collection.update_metadata!(
        next_indexing_embedding_model: { model_ref: 'text_embedding_005_vertex', field: 'test_field_456' }
      )
      Ai::ActiveContext::Queues::Code.push([failing_ref])

      allow(::ActiveContext).to receive_message_chain(:adapter, :search)
        .and_return([{ 'id' => identifier_fail, 'content' => 'test content' }])
      allow(mock_embeddings_llm).to receive(:execute).and_raise(StandardError, 'Embeddings generation failed')

      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(ActiveContext::RetryQueue.queue_size).to eq(1)

      allow(mock_embeddings_llm).to receive(:execute).and_return([[1, 2, 3]])
      processed_doc = nil
      expect(bulk_processor).to receive(:process) { |ref| processed_doc = ref.documents.first }

      travel(ActiveContext::RetryQueue.processing_delay + 1.second) do
        Ai::ActiveContext::BulkProcessWorker.perform_async('ActiveContext::RetryQueue', shard)
      end

      expect(processed_doc).to have_key(:test_field_123)
      expect(processed_doc).to have_key(:test_field_456)
    end
  end

  shared_examples 'embedding only the current model during a migration' do
    it 'only requests embeddings for the current model through the real queue pipeline' do
      collection.update_metadata!(
        next_indexing_embedding_model: { model_ref: 'text_embedding_005_vertex', field: 'test_field_456' }
      )

      search_response = [{ 'id' => identifier_success, 'content' => 'test content' }]
      allow(::ActiveContext).to receive_message_chain(:adapter, :search).and_return(search_response)

      processed_doc = nil
      expect(bulk_processor).to receive(:process) { |ref| processed_doc = ref.documents.first }

      Ai::ActiveContext::Queues::Code.push([successful_ref])
      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(processed_doc).to have_key(:test_field_123)
      expect(processed_doc).not_to have_key(:test_field_456)
    end
  end

  shared_examples 'skipping refs that already have embeddings' do
    it 'embeds only the refs that are not already embedded' do
      allow(::Ai::ActiveContext::Collections::Code).to receive(:search)
        .and_return([{ 'id' => identifier_success }])
      allow(::ActiveContext).to receive_message_chain(:adapter, :search)
        .and_return([{ 'id' => identifier_fail, 'content' => 'other content' }])

      expect(embeddings_llm_class).to receive(:new).with(
        ['other content'],
        hash_including(
          user: nil,
          root_namespace_id: embeddings_request_root_namespace_id
        )
      )

      Ai::ActiveContext::Queues::Code.push([successful_ref, failing_ref])
      Ai::ActiveContext::BulkProcessWorker.perform_async('Ai::ActiveContext::Queues::Code', shard)

      expect(Ai::ActiveContext::Queues::Code.queue_size).to eq(0)
      expect(ActiveContext::RetryQueue.queue_size).to eq(0)
      expect(ActiveContext::DeadQueue.queue_size).to eq(0)
    end
  end

  context 'when in saas' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    let(:embeddings_request_root_namespace_id) { root_namespace.id }

    include_examples 'successful processing'
    include_examples 'failure and retry flow'
    include_examples 'dead queue is not processed'
    include_examples 'multiple failures and successes'
    include_examples 'embedding only the current model during a migration'
    include_examples 'RetryQueue requests both models during a migration'
    include_examples 'skipping refs that already have embeddings'
  end

  context 'when not in saas' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    let(:embeddings_request_root_namespace_id) { nil }

    include_examples 'successful processing'
    include_examples 'failure and retry flow'
    include_examples 'dead queue is not processed'
    include_examples 'multiple failures and successes'
    include_examples 'embedding only the current model during a migration'
    include_examples 'RetryQueue requests both models during a migration'
    include_examples 'skipping refs that already have embeddings'
  end
end
