# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::AiAuditEvents::Streamer, feature_category: :audit_events do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let(:ai_audit_event) { build(:audit_events_ai_audit_event, target_project: project) }
  let(:ai_audit_events) { [ai_audit_event] }

  describe '.stream' do
    subject(:stream) { described_class.stream(ai_audit_events) }

    before do
      stub_licensed_features(external_audit_events: true)
    end

    context 'when the instance setting is disabled (default)' do
      before do
        create(:audit_events_group_external_streaming_destination, group: group)
      end

      it 'does not enqueue the streaming worker' do
        expect(::AuditEvents::AiAuditEventStreamingWorker).not_to receive(:perform_async)

        stream
      end
    end

    context 'when the instance setting is enabled' do
      before do
        ::Ai::Setting.for_organization(project.organization).update!(ai_audit_events_streaming_enabled: true)
      end

      context 'when there are no streaming destinations' do
        it 'does not enqueue the streaming worker' do
          expect(::AuditEvents::AiAuditEventStreamingWorker).not_to receive(:perform_async)

          stream
        end
      end

      context 'when the group has a streaming destination' do
        let!(:destination) { create(:audit_events_group_external_streaming_destination, group: group) }

        it 'enqueues the worker with the streaming JSON payload' do
          expect(::AuditEvents::AiAuditEventStreamingWorker)
            .to receive(:perform_async).with(ai_audit_event.streaming_json)

          stream
        end

        context 'when the destination only allows another event type' do
          before do
            create(:audit_events_group_event_type_filters,
              external_streaming_destination: destination, audit_event_type: 'ai_tool_invoked')
          end

          it 'does not enqueue the streaming worker' do
            expect(::AuditEvents::AiAuditEventStreamingWorker).not_to receive(:perform_async)

            stream
          end
        end

        context 'when the external_audit_events feature is not available' do
          before do
            stub_licensed_features(external_audit_events: false)
          end

          it 'does not enqueue the streaming worker' do
            expect(::AuditEvents::AiAuditEventStreamingWorker).not_to receive(:perform_async)

            stream
          end
        end

        context 'with a batch of events' do
          let(:ai_audit_events) do
            [
              ai_audit_event,
              build(:audit_events_ai_audit_event, target_project: project),
              build(:audit_events_ai_audit_event, target_project: project, event_name: 'ai_tool_invoked')
            ]
          end

          it 'enqueues one job per event' do
            expect(::AuditEvents::AiAuditEventStreamingWorker).to receive(:perform_async).exactly(3).times

            stream
          end

          it 'checks the destinations once per event name' do
            expect(::AuditEvents::ExternalDestinationStreamer).to receive(:new).twice.and_call_original

            stream
          end

          it 'reads the streaming setting once' do
            expect(::Ai::Setting).to receive(:for_organization_read_only).once.and_call_original

            stream
          end
        end

        context 'with a batch spanning two projects' do
          let_it_be(:other_group) { create(:group) }
          let_it_be(:other_project) { create(:project, group: other_group) }
          let(:other_event) { build(:audit_events_ai_audit_event, target_project: other_project) }
          let(:ai_audit_events) { [ai_audit_event, other_event] }

          it 'only enqueues events whose top-level group has a destination' do
            expect(::AuditEvents::AiAuditEventStreamingWorker)
              .to receive(:perform_async).with(ai_audit_event.streaming_json)
            expect(::AuditEvents::AiAuditEventStreamingWorker)
              .not_to receive(:perform_async).with(other_event.streaming_json)

            stream
          end
        end

        context 'with a namespace-scoped event' do
          let(:ai_audit_event) do
            build(:audit_events_ai_audit_event, target_project: project, project_id: nil, namespace_id: group.id)
          end

          it 'enqueues the worker with the streaming JSON payload' do
            expect(::AuditEvents::AiAuditEventStreamingWorker)
              .to receive(:perform_async).with(ai_audit_event.streaming_json)

            stream
          end
        end
      end

      context 'when the instance has a streaming destination' do
        before do
          create(:audit_events_instance_external_streaming_destination)
        end

        it 'enqueues the streaming worker' do
          expect(::AuditEvents::AiAuditEventStreamingWorker)
            .to receive(:perform_async).with(ai_audit_event.streaming_json)

          stream
        end
      end

      context 'when SilentMode is enabled' do
        before do
          create(:audit_events_group_external_streaming_destination, group: group)
          allow(::Gitlab::SilentMode).to receive(:enabled?).and_return(true)
        end

        it 'does not enqueue the worker' do
          expect(::AuditEvents::AiAuditEventStreamingWorker).not_to receive(:perform_async)

          stream
        end
      end
    end
  end
end
