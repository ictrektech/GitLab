# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::BaseStreamer, feature_category: :audit_events do
  let_it_be(:audit_event) { create(:audit_events_group_audit_event) }
  let(:event_type) { 'delete_issue' }
  let(:streamer) { described_class.new(event_type, audit_event) }

  describe '#initialize' do
    it 'sets audit operation and event' do
      expect(streamer.event_type).to eq(event_type)
      expect(streamer.audit_event).to eq(audit_event)
    end
  end

  describe '#streamable?' do
    it 'raises NotImplementedError' do
      expect { streamer.streamable? }.to raise_error(NotImplementedError)
    end
  end

  describe '#destinations' do
    it 'raises NotImplementedError' do
      expect { streamer.send(:destinations) }.to raise_error(NotImplementedError)
    end
  end

  describe '#execute' do
    let(:destination) { build(:external_audit_event_destination, group: create(:group)) }
    let(:test_streamer) do
      dest = destination
      Class.new(described_class) do
        def streamable?
          true
        end

        define_method(:destinations) { [dest] }
      end
    end

    subject(:execute) { test_streamer.new(event_type, audit_event).execute }

    context 'when not streamable' do
      let(:test_streamer) do
        Class.new(described_class) do
          def streamable?
            false
          end

          def destinations
            []
          end
        end
      end

      it 'does not stream to destinations' do
        expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:new)
        execute
      end
    end

    context 'when streamable' do
      before do
        allow(destination).to receive(:category).and_return('http')
        stub_feature_flags(audit_event_streaming_via_nats: false)
      end

      context 'when destination is allowed to stream' do
        before do
          allow(destination).to receive(:allowed_to_stream?).and_return(true)
        end

        it 'streams to destinations' do
          expect_next_instance_of(AuditEvents::Streaming::Destinations::HttpStreamDestination) do |streamer|
            expect(streamer).to receive(:deliver)
              .and_return(AuditEvents::Streaming::Destinations::BaseStreamDestination::Outcome.new(nil, nil))
          end

          execute
        end
      end

      context 'when destination is not allowed to stream' do
        before do
          allow(destination).to receive(:allowed_to_stream?).and_return(false)
        end

        it 'does not stream to destinations' do
          expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:new)

          execute
        end
      end

      context 'when the destination circuit breaker is open' do
        before do
          allow(destination).to receive(:allowed_to_stream?).and_return(true)
          allow(AuditEvents::Streaming::CircuitBreaker)
            .to receive(:reject_open).with([destination]).and_return([])
        end

        it 'does not stream to destinations whose circuit is open' do
          expect(AuditEvents::Streaming::Destinations::HttpStreamDestination).not_to receive(:new)

          execute
        end
      end
    end
  end

  describe '#track_and_stream' do
    let(:destination) { build(:external_audit_event_destination, group: create(:group)) }
    let(:outcome_class) { AuditEvents::Streaming::Destinations::BaseStreamDestination::Outcome }
    let(:context) do
      hash_including(
        audit_event_id: audit_event.id.to_s,
        destination_id: destination.id,
        destination_name: destination.name,
        destination_category: 'http',
        error_category: error_category
      )
    end

    before do
      allow(destination).to receive(:category).and_return('http')
    end

    context 'when the delivery succeeds' do
      let(:response) { instance_double(HTTParty::Response, code: 413) }

      before do
        allow(streamer).to receive(:stream_to_destination).and_return(outcome_class.new(nil, nil, response))
      end

      it 'logs success with audit event, destination and response context' do
        expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
          message: 'Audit event streamed',
          audit_event_id: audit_event.id.to_s,
          destination_id: destination.id,
          destination_name: destination.name,
          destination_category: 'http',
          event_type: event_type,
          Labkit::Fields::HTTP_STATUS_CODE => 413
        ))

        streamer.send(:track_and_stream, destination)
      end

      context 'when the destination response has no status code' do
        let(:response) { Object.new }

        it 'logs success with a nil status' do
          expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
            Labkit::Fields::HTTP_STATUS_CODE => nil
          ))

          streamer.send(:track_and_stream, destination)
        end
      end

      context 'when the audit event is not persisted' do
        let(:audit_event) { build(:audit_events_group_audit_event, stream_id: 'stream-uuid') }

        it 'logs the stream id as the audit event id' do
          expect(Gitlab::AppLogger).to receive(:info).with(hash_including(audit_event_id: 'stream-uuid'))

          streamer.send(:track_and_stream, destination)
        end
      end

      it 'records a circuit breaker success and does not report anything', :aggregate_failures do
        expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_success).with(destination)
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
        expect(Gitlab::ErrorTracking).not_to receive(:log_exception)

        streamer.send(:track_and_stream, destination)
      end
    end

    context 'when the delivery fails on the destination side' do
      let(:error) { Errno::ECONNREFUSED.new('connection refused') }
      let(:error_category) { :connection }

      before do
        allow(streamer).to receive(:stream_to_destination).and_return(outcome_class.new(error, error_category))
      end

      it 'logs the error with its class, records a breaker failure and does not report to Sentry',
        :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:log_exception).with(error, context)
        expect(AuditEvents::Streaming::CircuitBreaker).to receive(:record_failure).with(destination)
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        streamer.send(:track_and_stream, destination)
      end
    end

    context 'when the delivery fails on the GitLab side' do
      let(:error) { RuntimeError.new('bug') }
      let(:error_category) { :internal_error }

      before do
        allow(streamer).to receive(:stream_to_destination).and_return(outcome_class.new(error, error_category))
      end

      it 'reports the error with its class and leaves the breaker alone', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, context)
        expect(AuditEvents::Streaming::CircuitBreaker).not_to receive(:record_failure)

        streamer.send(:track_and_stream, destination)
      end
    end

    context 'when streaming raises before delivery' do
      let(:error) { ArgumentError.new('Stream destination class for category not found: invalid') }
      let(:error_category) { :internal_error }

      before do
        allow(streamer).to receive(:stream_to_destination).and_raise(error)
      end

      it 'reports it as an internal error and does not raise', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, context)

        expect { streamer.send(:track_and_stream, destination) }.not_to raise_error
      end
    end

    context 'when track_audit_event fails' do
      let(:error) { StandardError.new('internal event tracking error') }
      let(:error_category) { :internal_error }

      before do
        allow(streamer).to receive(:track_audit_event).and_raise(error)
      end

      it 'reports it as an internal error and does not attempt to stream', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, context)
        expect(streamer).not_to receive(:stream_to_destination)

        expect { streamer.send(:track_and_stream, destination) }.not_to raise_error
      end
    end
  end

  describe '#stream_to_destination' do
    let(:destination) { create(:external_audit_event_destination, group: create(:group)) }

    subject(:stream_to_destination) { streamer.send(:stream_to_destination, destination) }

    before do
      allow(destination).to receive(:category).and_return('http')
    end

    context 'when destination category is valid' do
      context 'when the batch-schema feature flag is disabled (legacy single-object)' do
        before do
          stub_feature_flags(audit_event_streaming_via_nats: false)
        end

        it 'streams a single-object body' do
          expect_next_instance_of(AuditEvents::Streaming::Destinations::HttpStreamDestination,
            event_type, audit_event, destination) do |stream_dest|
            expect(stream_dest).to receive(:deliver).with(batch_schema: false)
          end

          stream_to_destination
        end
      end

      context 'when the batch-schema feature flag is enabled for the group' do
        before do
          allow(::Gitlab::Nats).to receive(:enabled?).and_return(true)
          stub_feature_flags(audit_event_streaming_via_nats: audit_event.root_group_entity)
        end

        it 'streams using the batch (array) schema so it matches the NATS path' do
          expect_next_instance_of(AuditEvents::Streaming::Destinations::HttpStreamDestination,
            event_type, audit_event, destination) do |stream_dest|
            expect(stream_dest).to receive(:deliver).with(batch_schema: true)
          end

          stream_to_destination
        end
      end

      context 'when the event is instance-scoped (no root group)' do
        before do
          allow(::Gitlab::Nats).to receive(:enabled?).and_return(true)
          allow(audit_event).to receive(:root_group_entity).and_return(nil)
        end

        it 'checks the flag against :instance and uses the batch schema when enabled' do
          expect(::Feature).to receive(:enabled?)
            .with(:audit_event_streaming_via_nats, :instance).and_return(true)
          expect_next_instance_of(AuditEvents::Streaming::Destinations::HttpStreamDestination,
            event_type, audit_event, destination) do |stream_dest|
            expect(stream_dest).to receive(:deliver).with(batch_schema: true)
          end

          stream_to_destination
        end
      end

      context 'when NATS is not enabled (schema switch must not apply)' do
        before do
          allow(::Gitlab::Nats).to receive(:enabled?).and_return(false)
          stub_feature_flags(audit_event_streaming_via_nats: audit_event.root_group_entity)
        end

        it 'keeps the single-object body even with the flag on' do
          expect_next_instance_of(AuditEvents::Streaming::Destinations::HttpStreamDestination,
            event_type, audit_event, destination) do |stream_dest|
            expect(stream_dest).to receive(:deliver).with(batch_schema: false)
          end

          stream_to_destination
        end
      end
    end

    context 'when destination category is aws' do
      before do
        allow(destination).to receive(:category).and_return('aws')
        stub_feature_flags(audit_event_streaming_via_nats: false)
      end

      it 'uses AmazonS3StreamDestination' do
        expect_next_instance_of(AuditEvents::Streaming::Destinations::AmazonS3StreamDestination,
          event_type, audit_event, destination) do |stream_dest|
          expect(stream_dest).to receive(:deliver).with(batch_schema: false)
        end

        stream_to_destination
      end
    end

    context 'when destination category is gcp' do
      before do
        allow(destination).to receive(:category).and_return('gcp')
        stub_feature_flags(audit_event_streaming_via_nats: false)
      end

      it 'uses GoogleCloudLoggingStreamDestination' do
        expect_next_instance_of(AuditEvents::Streaming::Destinations::GoogleCloudLoggingStreamDestination,
          event_type, audit_event, destination) do |stream_dest|
          expect(stream_dest).to receive(:deliver).with(batch_schema: false)
        end

        stream_to_destination
      end
    end

    context 'when destination category is invalid' do
      before do
        allow(destination).to receive(:category).and_return('invalid')
      end

      it 'raises ArgumentError' do
        expect { stream_to_destination }
          .to raise_error(ArgumentError, 'Stream destination class for category not found: invalid')
      end
    end
  end

  describe '#track_audit_event' do
    subject(:track_audit_event) { streamer.send(:track_audit_event) }

    using RSpec::Parameterized::TableSyntax

    context 'with different audit operations' do
      where(:operation, :internal) do
        'delete_epic'       | true
        'delete_issue'      | true
        'delete_merge_request' | true
        'delete_work_item'  | true
        'project_created'   | false
        'unknown_operation' | false
      end

      with_them do
        let(:event_type) { operation }

        it 'tracks internal events appropriately' do
          if internal
            expect(streamer).to receive(:track_internal_event)
              .with('trigger_audit_event', additional_properties: { label: operation })
          else
            expect(streamer).not_to receive(:track_internal_event)
          end

          track_audit_event
        end
      end
    end
  end
end
