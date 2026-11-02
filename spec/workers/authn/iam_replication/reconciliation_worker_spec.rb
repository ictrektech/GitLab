# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamReplication::ReconciliationWorker, :clean_gitlab_redis_shared_state,
  feature_category: :system_access do
  subject(:worker) { described_class.new }

  it { is_expected.to be_a(CronjobQueue) }

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :always

  shared_examples 'a reconciliation sweep' do |entity_type:, upsert_method:, factory:, attributes: {}|
    let_it_be(:records) { create_list(factory, 3, **attributes) }

    # Applications created in an example are also sent through Layer 2.
    let(:client) { instance_double(Authn::IamService::GrpcClient, upsert_oauth_application: nil) }
    let(:upserted_ids) { [] }
    let(:cursor_key) { "authn:iam_replication:reconciliation:last_processed_id:#{entity_type}" }

    def cursor
      Gitlab::Redis::SharedState.with { |redis| redis.get(cursor_key) }
    end

    def store_cursor(id)
      Gitlab::Redis::SharedState.with { |redis| redis.set(cursor_key, id) }
    end

    def sent_ids(request)
      request.fetch(:clients, [request]).pluck(:source_id)
    end

    def record_upsert(request)
      upserted_ids.concat(sent_ids(request))
      ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceBulkUpsertClientsResponse.new(
        results: sent_ids(request).map { { reason: :REASON_WRITTEN } }
      )
    end

    before do
      allow(Authn::IamAuthService).to receive(:enabled?).and_return(true)
      allow(Authn::IamService::GrpcClient).to receive(:new).and_return(client)
      allow(client).to receive(upsert_method) { |**request| record_upsert(request) }
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [entity_type] }
    end

    it 'is scheduled' do
      expect(Gitlab::SidekiqConfig::CronJobs.config.jobs.values)
        .to include(hash_including('class' => described_class.name, 'args' => [entity_type]))
    end

    it 'checks the table it sweeps on database health' do
      attrs = described_class.database_health_check_attrs

      expect(attrs[:block].call([entity_type], attrs[:gitlab_schema], attrs[:tables]))
        .to eq([attrs[:gitlab_schema], [records.first.class.table_name]])
    end

    it 'upserts every record' do
      worker.perform(entity_type)

      expect(upserted_ids).to match_array(records.map(&:id))
    end

    it 'does not run a query per record', :use_sql_query_cache do
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { worker.perform(entity_type) }

      create_list(factory, 2, **attributes)

      expect { worker.perform(entity_type) }.not_to exceed_all_query_limit(control)
    end

    it 'logs the result' do
      stub_config_cell(id: 1)

      expect(worker).to receive(:log_extra_metadata_on_done).with(:result, hash_including(
        delivered: 3, rows: 3, entity_type: entity_type, layer: 4, cell_id: 1, over_time: false, last_processed_id: 0
      ))

      worker.perform(entity_type)
    end

    it 'resets the cursor after a complete pass' do
      worker.perform(entity_type)

      expect(cursor).to eq('0')
    end

    context 'when a cursor is stored' do
      it 'resumes after it' do
        store_cursor(records.first.id)

        worker.perform(entity_type)

        expect(upserted_ids).to match_array(records.drop(1).map(&:id))
      end

      it 'logs it as last_processed_id' do
        store_cursor(records.first.id)

        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:result, hash_including(last_processed_id: records.first.id))

        worker.perform(entity_type)
      end

      context 'when it is past the last record' do
        it 'upserts nothing and resets it', :aggregate_failures do
          store_cursor(records.last.id)

          worker.perform(entity_type)

          expect(upserted_ids).to be_empty
          expect(cursor).to eq('0')
        end
      end
    end

    context 'when the records of a batch are deleted during the pass' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
        stub_const("#{described_class}::BULK_BATCH_SIZE", 1)

        allow(client).to receive(upsert_method) do |**request|
          records.first.class.where(id: records.drop(1).map(&:id)).delete_all
          record_upsert(request)
        end
      end

      it 'skips the empty batch', :aggregate_failures do
        worker.perform(entity_type)

        expect(upserted_ids).to eq([records.first.id])
        expect(client).to have_received(upsert_method).once
      end
    end

    context 'when the runtime limit is reached' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
        stub_const("#{described_class}::BULK_BATCH_SIZE", 1)

        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive_messages(over_time?: true, was_over_time?: true)
        end
      end

      it 'keeps the cursor and logs over_time', :aggregate_failures do
        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:result, hash_including(delivered: 1, over_time: true))

        worker.perform(entity_type)

        expect(cursor).to eq(records.first.id.to_s)
      end
    end

    context 'when IAM is unhealthy' do
      let(:error) { Authn::IamService::GrpcClient::RequestError.new('unhealthy', reason: :unavailable) }

      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
        stub_const("#{described_class}::BULK_BATCH_SIZE", 1)

        allow(client).to receive(upsert_method) do |**request|
          raise error if sent_ids(request).include?(records.second.id)

          record_upsert(request)
        end
      end

      it 'raises, keeps the cursor at the last complete batch, and logs the records before the error',
        :aggregate_failures do
        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:result, hash_including(delivered: 1, over_time: false))

        expect { worker.perform(entity_type) }.to raise_error(error)
        expect(cursor).to eq(records.first.id.to_s)
      end
    end

    context 'when iam_data_replication is disabled' do
      before do
        stub_feature_flags(iam_data_replication: false)
      end

      it 'does not upsert' do
        worker.perform(entity_type)

        expect(client).not_to have_received(upsert_method)
      end
    end

    context 'when the IAM auth service is disabled' do
      before do
        allow(Authn::IamAuthService).to receive(:enabled?).and_return(false)
      end

      it 'does not upsert' do
        worker.perform(entity_type)

        expect(client).not_to have_received(upsert_method)
      end
    end
  end

  context 'with oauth_application' do
    include_examples 'a reconciliation sweep',
      entity_type: 'oauth_application', upsert_method: :bulk_upsert_oauth_applications, factory: :oauth_application

    context 'with more records than BATCH_SIZE' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
      end

      it 'sends them in one bulk call' do
        worker.perform('oauth_application')

        expect(client).to have_received(:bulk_upsert_oauth_applications).once
      end
    end

    context 'when IAM refuses a record' do
      before do
        allow(client).to receive(:bulk_upsert_oauth_applications) do |clients:|
          refusals = { records.first.id => { reason: :REASON_INVALID, message: 'bad' } }

          ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceBulkUpsertClientsResponse.new(
            results: clients.map { |sent| refusals.fetch(sent[:source_id], { reason: :REASON_WRITTEN }) }
          )
        end
        allow(Gitlab::AuthLogger).to receive(:warn)
      end

      it 'logs and counts the refused record', :aggregate_failures do
        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:result, hash_including(delivered: 2, invalid_request: 1))

        worker.perform('oauth_application')

        expect(Gitlab::AuthLogger).to have_received(:warn).once
        expect(Gitlab::AuthLogger).to have_received(:warn).once.with(hash_including(
          'entity_id' => records.first.id, 'skip_reason' => :invalid_request, 'skip_message' => 'bad',
          'skip_iam_reason' => 'REASON_INVALID'
        ))
      end
    end

    context 'when IAM refuses the whole call' do
      let(:error) { Authn::IamService::GrpcClient::RequestError.new('refused', reason: :invalid_request) }

      before do
        allow(client).to receive(:bulk_upsert_oauth_applications).and_raise(error)
      end

      it 'raises instead of skipping the records' do
        expect { worker.perform('oauth_application') }.to raise_error(error)
      end
    end

    context 'when a batch raises an unexpected error' do
      let(:error) { StandardError.new('boom') }

      before do
        stub_const("#{described_class}::BULK_BATCH_SIZE", 1)

        allow(client).to receive(:bulk_upsert_oauth_applications) do |**request|
          raise error if sent_ids(request).include?(records.second.id)

          record_upsert(request)
        end
      end

      it 'raises and keeps the cursor at the last complete batch', :aggregate_failures do
        expect { worker.perform('oauth_application') }.to raise_error(error)
        expect(cursor).to eq(records.first.id.to_s)
      end
    end
  end

  context 'with oauth_access_token' do
    include_examples 'a reconciliation sweep',
      entity_type: 'oauth_access_token', upsert_method: :upsert_oauth_refresh_token,
      factory: :oauth_access_token, attributes: { use_refresh_token: true }

    context 'when IAM rejects a record' do
      where(reason: %i[invalid_request failed_precondition])

      with_them do
        before do
          allow(client).to receive(:upsert_oauth_refresh_token).with(hash_including(source_id: records.first.id))
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('rejected', reason: reason))
          allow(Gitlab::AuthLogger).to receive(:warn)
        end

        it 'logs and counts the record, and upserts the others', :aggregate_failures do
          expect(worker).to receive(:log_extra_metadata_on_done)
            .with(:result, hash_including(:delivered => 2, reason => 1))

          worker.perform('oauth_access_token')

          expect(Gitlab::AuthLogger).to have_received(:warn)
            .with(hash_including('entity_id' => records.first.id, 'skip_reason' => reason))
          expect(Gitlab::AuthLogger).to have_received(:warn).with(hash_excluding('skip_message', 'skip_iam_reason'))
          expect(upserted_ids).to match_array(records.drop(1).map(&:id))
        end
      end
    end

    context 'when a record raises an unexpected error' do
      before do
        allow(client).to receive(:upsert_oauth_refresh_token).with(hash_including(source_id: records.first.id))
          .and_raise(StandardError)
      end

      it 'tracks and counts the error, and upserts the others', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), entity_type: 'oauth_access_token', entity_id: records.first.id)
        expect(worker).to receive(:log_extra_metadata_on_done)
          .with(:result, hash_including(delivered: 2, error: 1))

        worker.perform('oauth_access_token')

        expect(upserted_ids).to match_array(records.drop(1).map(&:id))
      end
    end

    context 'when a batch has no token in the scope' do
      let_it_be(:token_out_of_scope) { create(:oauth_access_token, refresh_token: nil) }

      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
        store_cursor(records.last.id)

        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive_messages(over_time?: true, was_over_time?: true)
        end
      end

      it 'moves the cursor past the batch', :aggregate_failures do
        worker.perform('oauth_access_token')

        expect(upserted_ids).to be_empty
        expect(cursor).to eq(token_out_of_scope.id.to_s)
      end
    end
  end
end
