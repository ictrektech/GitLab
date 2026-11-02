# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::AiAuditEvents::PostgresqlFinder, feature_category: :duo_agent_platform do
  let_it_be(:workflow) { create(:duo_workflows_workflow) }
  let_it_be(:other_workflow) { create(:duo_workflows_workflow) }

  let_it_be(:event_oldest) do
    create(:audit_events_ai_audit_event, workflow_id: workflow.id, created_at: 3.minutes.ago)
  end

  let_it_be(:event_middle) do
    create(:audit_events_ai_audit_event, workflow_id: workflow.id, created_at: 2.minutes.ago)
  end

  let_it_be(:event_newest) do
    create(:audit_events_ai_audit_event, workflow_id: workflow.id, created_at: 1.minute.ago)
  end

  let_it_be(:event_other_workflow) do
    create(:audit_events_ai_audit_event, workflow_id: other_workflow.id)
  end

  subject(:execute) { described_class.new(workflow: workflow).execute }

  it 'returns audit events scoped to the workflow, most recent first' do
    expect(execute).to eq([event_newest, event_middle, event_oldest])
  end

  it 'does not include events from other workflows' do
    expect(execute).not_to include(event_other_workflow)
  end

  context 'with a lower bound on created_at' do
    subject(:execute) { described_class.new(workflow: workflow, created_after: event_middle.created_at).execute }

    it 'excludes older events' do
      expect(execute).to eq([event_newest, event_middle])
    end
  end

  context 'with an AI governance session ID' do
    let_it_be(:session_id) { non_existing_record_id }

    let_it_be(:session_event_old) do
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id,
        created_at: 2.days.ago)
    end

    let_it_be(:session_event_new) do
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id,
        created_at: 1.minute.ago)
    end

    let_it_be(:session_event_older) do
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id,
        created_at: 1.hour.ago)
    end

    let_it_be(:other_session_event) do
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id - 1)
    end

    subject(:execute) do
      described_class.new(ai_governance_session_id: session_id, created_after: 1.day.ago).execute
    end

    it 'returns the events of the session after the lower bound, most recent first' do
      expect(execute).to eq([session_event_new, session_event_older])
    end
  end

  describe '.counts_for_workflows' do
    it 'counts the events of each workflow' do
      expect(described_class.counts_for_workflows([workflow.id, other_workflow.id]))
        .to eq(workflow.id => 3, other_workflow.id => 1)
    end

    it 'excludes events before the lower bound and workflows without events' do
      expect(described_class.counts_for_workflows([workflow.id, non_existing_record_id],
        min_created_at: event_middle.created_at)).to eq(workflow.id => 2)
    end

    it 'returns an empty hash without IDs' do
      expect(described_class.counts_for_workflows([])).to eq({})
    end
  end

  describe '.counts_for_sessions' do
    let_it_be(:session_id) { non_existing_record_id }

    before_all do
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id,
        created_at: 2.days.ago)
      create_list(:audit_events_ai_audit_event, 2, workflow_id: nil, ai_governance_session_id: session_id,
        created_at: 1.minute.ago)
      create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: session_id - 1)
      # Shares its number with the session ID, but belongs to a workflow.
      create(:audit_events_ai_audit_event, workflow_id: session_id)
    end

    it 'counts the events of each session' do
      expect(described_class.counts_for_sessions([session_id, session_id - 1]))
        .to eq(session_id => 3, (session_id - 1) => 1)
    end

    it 'excludes events before the lower bound and sessions without events' do
      expect(described_class.counts_for_sessions([session_id, session_id + 1], min_created_at: 1.day.ago))
        .to eq(session_id => 2)
    end

    it 'returns an empty hash without IDs' do
      expect(described_class.counts_for_sessions([])).to eq({})
    end
  end

  it 'requires exactly one of workflow or ai_governance_session_id', :aggregate_failures do
    expect { described_class.new }.to raise_error(ArgumentError)
    expect { described_class.new(workflow: workflow, ai_governance_session_id: 1) }.to raise_error(ArgumentError)
  end
end
