# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::Destinations::BaseStreamDestination, feature_category: :audit_events do
  let_it_be(:audit_event) { create(:audit_events_group_audit_event) }
  let(:event_type) { 'event_type' }
  let(:destination) { create(:audit_events_instance_external_streaming_destination, :http) }
  let(:base_destination) { described_class.new(event_type, audit_event, destination) }

  describe '#stream' do
    it 'raises NotImplementedError' do
      expect { base_destination.stream }.to raise_error(NotImplementedError)
    end
  end

  describe '#stream_batch' do
    it 'raises NotImplementedError' do
      expect { base_destination.stream_batch([]) }.to raise_error(NotImplementedError)
    end
  end

  describe '#deliver' do
    using RSpec::Parameterized::TableSyntax

    it 'returns a delivered outcome when stream succeeds', :aggregate_failures do
      allow(base_destination).to receive(:stream)

      outcome = base_destination.deliver

      expect(outcome).to be_delivered
      expect(outcome.error_category).to be_nil
    end

    it 'streams with the batch schema when asked' do
      expect(base_destination).to receive(:stream_as_batch)
      expect(base_destination).not_to receive(:stream)

      base_destination.deliver(batch_schema: true)
    end

    it 'hands the outcome and event count to the delivery hook' do
      allow(base_destination).to receive(:stream)

      expect(base_destination).to receive(:record_delivery).with(be_delivered, 1)

      base_destination.deliver
    end

    it 'keeps the settled outcome and reports a delivery hook failure to Sentry', :aggregate_failures do
      allow(base_destination).to receive(:stream)
      hook_error = RuntimeError.new('metrics bug')
      allow(base_destination).to receive(:record_delivery).and_raise(hook_error)

      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(hook_error)

      expect(base_destination.deliver).to be_delivered
    end

    it 'returns an internal error when classification itself raises', :aggregate_failures do
      allow(base_destination).to receive(:stream).and_raise(Errno::ECONNRESET)
      classification_error = NoMethodError.new('classifier bug')
      allow(base_destination).to receive(:classify_error).and_raise(classification_error)

      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      outcome = base_destination.deliver

      expect(outcome.error).to be(classification_error)
      expect(outcome.error_category).to eq(:internal_error)
    end

    context 'when stream raises' do
      where(:error, :expected_category) do
        Net::OpenTimeout.new                           | :timeout
        Gitlab::HTTP::ReadTotalTimeout.new             | :timeout
        Errno::ETIMEDOUT.new                           | :timeout
        Errno::ECONNREFUSED.new                        | :connection
        SocketError.new                                | :connection
        OpenSSL::SSL::SSLError.new                     | :connection
        URI::InvalidURIError.new('bad url')            | :invalid_config
        JSON::ParserError.new('bad json')              | :invalid_config
        Gitlab::HTTP::BlockedUrlError.new('blocked')   | :invalid_config
        Gitlab::HTTP::RedirectionTooDeep.new           | :invalid_config
        RuntimeError.new('bug')                        | :internal_error
      end

      with_them do
        it 'returns a failed outcome carrying the error and its category', :aggregate_failures do
          allow(base_destination).to receive(:stream).and_raise(error)

          outcome = base_destination.deliver

          expect(outcome).not_to be_delivered
          expect(outcome.error).to be(error)
          expect(outcome.error_category).to eq(expected_category)
        end
      end

      it 'treats a category outside the fixed set as an internal error so it cannot pass for a destination error' do
        allow(base_destination).to receive(:stream).and_raise(RuntimeError)
        allow(base_destination).to receive(:classify_error).and_return(:typo)

        expect(base_destination.deliver.error_category).to eq(:internal_error)
      end
    end
  end

  describe '#deliver_batch' do
    let(:base_destination) { described_class.for_batch(destination) }
    let(:bodies) { [{ 'id' => '1' }, { 'id' => '2' }] }

    it 'streams the batch and hands the outcome and batch size to the delivery hook', :aggregate_failures do
      expect(base_destination).to receive(:stream_batch).with(bodies)
      expect(base_destination).to receive(:record_delivery).with(be_delivered, 2)

      expect(base_destination.deliver_batch(bodies)).to be_delivered
    end

    it 'returns a failed outcome when stream_batch raises' do
      allow(base_destination).to receive(:stream_batch).and_raise(Errno::ECONNRESET)

      expect(base_destination.deliver_batch(bodies).error_category).to eq(:connection)
    end
  end

  describe '#request_body' do
    subject(:request_body) { base_destination.send(:request_body) }

    it 'returns json with required fields', :aggregate_failures do
      body = Gitlab::Json.parse(request_body)

      expect(body['event_type']).to eq(event_type)
      expect(body['id']).to eq(audit_event.id)
    end

    context 'when built in batch mode (no audit event)' do
      let(:base_destination) { described_class.for_batch(destination) }

      it 'raises ArgumentError' do
        expect { request_body }.to raise_error(ArgumentError, /requires a per-event instance/)
      end
    end

    context 'when the audit event has a blank database id' do
      before do
        allow(audit_event).to receive(:id).and_return(nil)
      end

      let(:uuid_format) { /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/ }

      context 'and it does not respond to stream_id' do
        before do
          allow(audit_event).to receive(:respond_to?).and_call_original
          allow(audit_event).to receive(:respond_to?).with(:stream_id).and_return(false)
        end

        it 'falls back to a generated UUID' do
          expect(Gitlab::Json.parse(request_body)['id']).to match(uuid_format)
        end
      end

      context 'and its stream_id is blank' do
        before do
          allow(audit_event).to receive(:stream_id).and_return(nil)
        end

        it 'falls back to a generated UUID' do
          expect(Gitlab::Json.parse(request_body)['id']).to match(uuid_format)
        end
      end

      context 'and its stream_id is present' do
        before do
          allow(audit_event).to receive(:stream_id).and_return('upstream-stream-id')
        end

        it 'uses the upstream stream_id' do
          expect(Gitlab::Json.parse(request_body)['id']).to eq('upstream-stream-id')
        end
      end
    end
  end
end
