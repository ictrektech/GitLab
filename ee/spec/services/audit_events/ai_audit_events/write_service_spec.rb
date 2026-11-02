# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::AiAuditEvents::WriteService, feature_category: :audit_events do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }

  let(:event_id_one) { SecureRandom.uuid }
  let(:event_id_two) { SecureRandom.uuid }
  let(:event_time_one) { DateTime.parse('2026-01-01T00:00:00Z') }
  let(:event_time_two) { DateTime.parse('2026-01-01T00:00:01Z') }

  let(:serialized_events) do
    [
      {
        'cloud_event_id' => event_id_one,
        'event_name' => 'ai_llm_input_sent',
        'created_at' => event_time_one.iso8601,
        'author_id' => user.id,
        'project_id' => project.id,
        'namespace_id' => nil,
        'ip_address' => nil,
        'workflow_id' => workflow.id,
        'details' => { 'model' => 'claude-3' }
      },
      {
        'cloud_event_id' => event_id_two,
        'event_name' => 'ai_llm_response_received',
        'created_at' => event_time_two.iso8601,
        'author_id' => user.id,
        'project_id' => project.id,
        'namespace_id' => nil,
        'ip_address' => nil,
        'workflow_id' => workflow.id,
        'details' => {}
      }
    ]
  end

  def execute_service(events)
    described_class.new(events&.map { |attrs| ::AuditEvents::AiAuditEvent.new(attrs) }).execute
  end

  describe '#execute' do
    context 'when ClickHouse is not globally enabled for analytics' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        project.project_setting.update!(ai_audit_events_storage_enabled: true)
      end

      it 'persists records to Postgres' do
        expect { execute_service(serialized_events) }
          .to change { ::AuditEvents::AiAuditEvent.count }.by(2)

        persisted = ::AuditEvents::AiAuditEvent.where(cloud_event_id: [event_id_one, event_id_two])
        expect(persisted.pluck(:cloud_event_id)).to contain_exactly(event_id_one, event_id_two)
        expect(persisted.pluck(:event_name))
          .to contain_exactly('ai_llm_input_sent', 'ai_llm_response_received')
        expect(persisted.pluck(:workflow_id).uniq).to eq([workflow.id])
        expect(persisted.pluck(:author_id).uniq).to eq([user.id])
      end

      it 'deduplicates retried batches via the unique index' do
        execute_service(serialized_events)

        expect { execute_service(serialized_events) }
          .not_to change { ::AuditEvents::AiAuditEvent.count }
      end

      it 'increments STORED_COUNTER with store: :postgresql by the event count' do
        expect(described_class::STORED_COUNTER)
          .to receive(:increment).with({ store: :postgresql }, 2)

        execute_service(serialized_events)
      end

      it 'increments PG_FALLBACK_COUNTER by the event count' do
        allow(described_class::STORED_COUNTER).to receive(:increment)

        expect(described_class::PG_FALLBACK_COUNTER)
          .to receive(:increment).with({}, 2)

        execute_service(serialized_events)
      end

      it 'does not increment BUFFERED_COUNTER' do
        allow(described_class::STORED_COUNTER).to receive(:increment)

        expect(described_class::BUFFERED_COUNTER).not_to receive(:increment)

        execute_service(serialized_events)
      end
    end

    context 'when ClickHouse is globally enabled for analytics' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
        project.project_setting.update!(ai_audit_events_storage_enabled: true)
      end

      it 'buffers records to ClickHouse and does not insert into Postgres' do
        expect(ClickHouse::WriteBuffer).to receive(:add).with('ai_audit_events', anything).twice
        expect { execute_service(serialized_events) }.not_to change { ::AuditEvents::AiAuditEvent.count }
      end

      it 'increments BUFFERED_COUNTER by the actual buffered count, not the total event count',
        :clean_gitlab_redis_shared_state do
        # store_to_clickhouse returns false for an invalid record, so only the valid
        # event is buffered and counted.
        serialized_events.last['workflow_id'] = nil

        expect(described_class::BUFFERED_COUNTER).to receive(:increment).with({}, 1)

        execute_service(serialized_events)
      end

      it 'increments BUFFERED_COUNTER by the full event count when all records buffer successfully' do
        allow(ClickHouse::WriteBuffer).to receive(:add).and_return('OK')

        expect(described_class::BUFFERED_COUNTER).to receive(:increment).with({}, 2)

        execute_service(serialized_events)
      end

      it 'does not increment STORED_COUNTER or PG_FALLBACK_COUNTER' do
        allow(ClickHouse::WriteBuffer).to receive(:add).and_return('OK')
        allow(described_class::BUFFERED_COUNTER).to receive(:increment)

        expect(described_class::STORED_COUNTER).not_to receive(:increment)
        expect(described_class::PG_FALLBACK_COUNTER).not_to receive(:increment)

        execute_service(serialized_events)
      end
    end

    it 'streams each event via the Streamer' do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)

      expect(::AuditEvents::AiAuditEvents::Streamer)
        .to receive(:stream).with([kind_of(::AuditEvents::AiAuditEvent)] * 2)

      execute_service(serialized_events)
    end

    context 'when the storage setting gates persistence' do
      let(:logger) { instance_double(Gitlab::AuditJsonLogger) }

      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
        allow(Gitlab::AuditJsonLogger).to receive(:build).and_return(logger)
        allow(logger).to receive(:info)
      end

      context 'when storage is enabled for the project' do
        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: true)
        end

        it 'logs each event to the audit JSON log' do
          expect(logger).to receive(:info).with(hash_including(cloud_event_id: event_id_one)).ordered
          expect(logger).to receive(:info).with(hash_including(cloud_event_id: event_id_two)).ordered

          execute_service(serialized_events)
        end

        it 'logs a nil created_at when the event has none' do
          # A nil created_at has no partition, so stub the insert to reach the log step.
          allow(::AuditEvents::AiAuditEvent).to receive(:bulk_insert!)

          expect(logger).to receive(:info).with(hash_including(cloud_event_id: event_id_one, created_at: nil))

          execute_service([serialized_events.first.merge('created_at' => nil)])
        end
      end

      context 'when storage is disabled for the project' do
        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: false)
        end

        it 'does not persist the events' do
          expect { execute_service(serialized_events) }
            .not_to change { ::AuditEvents::AiAuditEvent.count }
        end

        it 'does not write the events to the audit JSON log' do
          expect(logger).not_to receive(:info)

          execute_service(serialized_events)
        end

        it 'still streams the events' do
          expect(::AuditEvents::AiAuditEvents::Streamer)
            .to receive(:stream).with([kind_of(::AuditEvents::AiAuditEvent)] * 2)

          execute_service(serialized_events)
        end
      end

      context 'when storage is enabled for only some events in the batch' do
        let_it_be_with_reload(:other_project) { create(:project) }

        let(:mixed_events) do
          [serialized_events.first, serialized_events.last.merge('project_id' => other_project.id)]
        end

        before do
          project.project_setting.update!(ai_audit_events_storage_enabled: true)
          other_project.project_setting.update!(ai_audit_events_storage_enabled: false)
        end

        it 'persists only the events whose scope has storage enabled' do
          execute_service(mixed_events)

          expect(::AuditEvents::AiAuditEvent.pluck(:cloud_event_id)).to contain_exactly(event_id_one)
        end

        it 'logs only the events whose scope has storage enabled' do
          expect(logger).to receive(:info).with(hash_including(cloud_event_id: event_id_one)).once
          expect(logger).not_to receive(:info).with(hash_including(cloud_event_id: event_id_two))

          execute_service(mixed_events)
        end
      end

      context 'when storage is disabled for a namespace-scoped event' do
        let_it_be_with_reload(:group) { create(:group) }

        let(:namespace_events) do
          [serialized_events.first.merge('project_id' => nil, 'namespace_id' => group.id)]
        end

        before do
          group.namespace_settings.update!(ai_audit_events_storage_enabled: false)
        end

        it 'does not persist the events' do
          expect { execute_service(namespace_events) }
            .not_to change { ::AuditEvents::AiAuditEvent.count }
        end

        it 'does not write the events to the audit JSON log' do
          expect(logger).not_to receive(:info)

          execute_service(namespace_events)
        end
      end

      context 'when the project and namespace cannot be resolved' do
        let(:unresolvable_events) do
          [serialized_events.first.merge('project_id' => non_existing_record_id, 'namespace_id' => nil)]
        end

        it 'does not persist the events' do
          expect { execute_service(unresolvable_events) }
            .not_to change { ::AuditEvents::AiAuditEvent.count }
        end

        it 'does not write the events to the audit JSON log' do
          expect(logger).not_to receive(:info)

          execute_service(unresolvable_events)
        end

        it 'still streams the events' do
          expect(::AuditEvents::AiAuditEvents::Streamer)
            .to receive(:stream).with([kind_of(::AuditEvents::AiAuditEvent)])

          execute_service(unresolvable_events)
        end
      end

      context 'when the event has neither a project nor a namespace' do
        let(:unscoped_events) do
          [serialized_events.first.merge('project_id' => nil, 'namespace_id' => nil)]
        end

        it 'does not persist the events' do
          expect { execute_service(unscoped_events) }
            .not_to change { ::AuditEvents::AiAuditEvent.count }
        end

        it 'still streams the events' do
          expect(::AuditEvents::AiAuditEvents::Streamer)
            .to receive(:stream).with([kind_of(::AuditEvents::AiAuditEvent)])

          execute_service(unscoped_events)
        end
      end
    end

    context 'when audit_events is blank' do
      it 'returns early without incrementing storage counters' do
        expect(::AuditEvents::AiAuditEvent).not_to receive(:bulk_insert!)
        expect(described_class::STORED_COUNTER).not_to receive(:increment)
        expect(described_class::BUFFERED_COUNTER).not_to receive(:increment)
        expect(described_class::PG_FALLBACK_COUNTER).not_to receive(:increment)

        execute_service([])
        execute_service(nil)
      end
    end
  end
end
