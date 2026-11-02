# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Search::Elastic RetryQueue and DeadQueue', :clean_gitlab_redis_shared_state,
  feature_category: :global_search do
  let(:ref_class) { ::Search::Elastic::DocumentReference }
  let(:fake_refs) { (1..3).map { |i| ref_class.new(Issue, i, "issue_#{i}", 'project_1') } }
  let(:successful_ref) { fake_refs[0] }
  let(:failing_ref) { fake_refs[1] }

  before do
    stub_ee_application_setting(elasticsearch_worker_number_of_shards: Elastic::ProcessBookkeepingService::SHARDS_MAX)
  end

  def expect_processing(*refs, failures: [])
    db_record = class_double(Issue, present?: true, preload_indexing_data: [])

    refs.each do |ref|
      allow(ref).to receive_messages(
        database_record: db_record,
        as_indexed_json: failures.include?(ref) ? nil : { id: ref.db_id },
        index_name: 'test-index',
        identifier: ref.es_id,
        routing: ref.es_parent,
        operation: :upsert
      )
    end

    bulk_indexer = instance_double(::Search::Elastic::BulkIndexer)
    allow(::Search::Elastic::BulkIndexer).to receive(:new).and_return(bulk_indexer)
    allow(bulk_indexer).to receive_messages(
      process: 100, # Return byte count
      flush: failures
    )
    allow(Search::Elastic::Reference).to receive(:preload_database_records).with(anything).and_return(refs)
  end

  describe 'failure and retry flow' do
    it 'moves failed refs to retry queue, then to dead queue on second failure' do
      Elastic::ProcessBookkeepingService.track!(failing_ref)

      expect_processing(failing_ref, failures: [failing_ref])

      expect(Elastic::ProcessBookkeepingService.queue_size).to eq(1)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(0)

      # First attempt - should move to retry queue
      Elastic::ProcessBookkeepingService.new.execute

      expect(Elastic::ProcessBookkeepingService.queue_size).to eq(0)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(1)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(0)

      expect_processing(failing_ref, failures: [failing_ref])

      # Second attempt from retry queue - should move to dead queue
      Search::Elastic::RetryQueue.new.execute

      expect(Elastic::ProcessBookkeepingService.queue_size).to eq(0)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(1)
    end
  end

  describe 'dead queue is not processed' do
    it 'keeps items in dead queue indefinitely' do
      Search::Elastic::DeadQueue.track!(failing_ref)

      expect(Search::Elastic::DeadQueue.queue_size).to eq(1)

      # Process other queues
      Elastic::ProcessBookkeepingService.new.execute
      Search::Elastic::RetryQueue.new.execute

      # Dead queue should remain unchanged
      expect(Search::Elastic::DeadQueue.queue_size).to eq(1)
    end
  end

  describe 'oldest_enqueued_at clock isolation' do
    it 'does not share its clock with the incremental queue, retry queue, or dead queue' do
      freeze_time do
        Elastic::ProcessBookkeepingService.track!(successful_ref)
        incremental_clock = Elastic::ProcessBookkeepingService.oldest_enqueued_at

        travel 65.seconds
        Search::Elastic::RetryQueue.track!(failing_ref)

        expect(Elastic::ProcessBookkeepingService.oldest_enqueued_at).to eq(incremental_clock)
        expect(Search::Elastic::RetryQueue.oldest_enqueued_at).not_to eq(incremental_clock)

        travel 65.seconds
        Search::Elastic::DeadQueue.track!(fake_refs[2])

        expect(Elastic::ProcessBookkeepingService.oldest_enqueued_at).to eq(incremental_clock)
        expect(Search::Elastic::DeadQueue.oldest_enqueued_at).not_to eq(incremental_clock)
      end
    end

    it 'does not clear the incremental clock when the retry queue drains' do
      Elastic::ProcessBookkeepingService.track!(successful_ref)
      Search::Elastic::RetryQueue.track!(failing_ref)

      expect(Elastic::ProcessBookkeepingService.oldest_enqueued_at).not_to be_nil

      expect_processing(failing_ref)
      Search::Elastic::RetryQueue.new.execute

      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)
      expect(Elastic::ProcessBookkeepingService.oldest_enqueued_at).not_to be_nil
    end
  end

  describe 'multiple failures and successes' do
    it 'handles mixed success and failure scenarios correctly' do
      Elastic::ProcessBookkeepingService.track!(successful_ref, failing_ref)

      expect_processing(successful_ref, failing_ref, failures: [failing_ref])

      expect(Elastic::ProcessBookkeepingService.queue_size).to eq(2)

      # First attempt - success processes, failure goes to retry queue
      Elastic::ProcessBookkeepingService.new.execute

      expect(Elastic::ProcessBookkeepingService.queue_size).to eq(0)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(1)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(0)

      expect_processing(failing_ref, failures: [failing_ref])

      # Second attempt from retry queue - failure goes to dead queue
      Search::Elastic::RetryQueue.new.execute

      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(1)
    end
  end

  describe 'ProcessInitialBookkeepingService' do
    it 'also routes failures through retry queue to dead queue' do
      Elastic::ProcessInitialBookkeepingService.track!(failing_ref)

      expect_processing(failing_ref, failures: [failing_ref])

      expect(Elastic::ProcessInitialBookkeepingService.queue_size).to eq(1)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)

      # First attempt
      Elastic::ProcessInitialBookkeepingService.new.execute

      expect(Elastic::ProcessInitialBookkeepingService.queue_size).to eq(0)
      expect(Search::Elastic::RetryQueue.queue_size).to eq(1)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(0)

      expect_processing(failing_ref, failures: [failing_ref])

      # Retry attempt
      Search::Elastic::RetryQueue.new.execute

      expect(Search::Elastic::RetryQueue.queue_size).to eq(0)
      expect(Search::Elastic::DeadQueue.queue_size).to eq(1)
    end
  end
end
