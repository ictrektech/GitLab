# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ProcessAuditEventsWorker, feature_category: :audit_events do
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

  subject(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [serialized_events] }

    before do
      # Storage is opt-in, so enable it here; otherwise the worker returns early
      # and the idempotency check no longer exercises the dedup path.
      project.project_setting.update!(ai_audit_events_storage_enabled: true)
    end
  end

  describe '#perform' do
    it 'passes the deserialized events to the write service' do
      service = instance_double(::AuditEvents::AiAuditEvents::WriteService)

      expect(::AuditEvents::AiAuditEvents::WriteService).to receive(:new) do |audit_events|
        expect(audit_events).to all(be_a(::AuditEvents::AiAuditEvent))
        expect(audit_events.map(&:cloud_event_id)).to eq([event_id_one, event_id_two])

        service
      end
      expect(service).to receive(:execute)

      worker.perform(serialized_events)
    end

    it 'persists records to Postgres when ClickHouse is not globally enabled for analytics' do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      project.project_setting.update!(ai_audit_events_storage_enabled: true)

      expect { worker.perform(serialized_events) }
        .to change { ::AuditEvents::AiAuditEvent.count }.by(2)
    end

    context 'when serialized_events is blank' do
      it 'does not call the write service' do
        expect(::AuditEvents::AiAuditEvents::WriteService).not_to receive(:new)

        worker.perform([])
        worker.perform(nil)
      end
    end
  end
end
