# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Governance::SessionArtifactExportService, :click_house, feature_category: :compliance_management do
  include Ai::Governance::SessionClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:session_started_at) { Time.utc(2026, 7, 1, 10) }

  let(:session_row) do
    ai_governance_session_row(id: 21, namespace: project.project_namespace, project: project, user: user,
      source: :claude_code_glab, flow_type: 'claude_code', agent_type: 'codex',
      session_started_at: session_started_at)
  end

  let(:session) do
    query = Ai::Governance::Sessions::ClickHouseFinder.new(
      current_user: user, namespace: project.project_namespace, params: { id: session_row[:id] }
    ).execute

    ClickHouse::Client.select(query, :main).first
  end

  let(:event_id) { SecureRandom.uuid }

  let(:current_user) { user }

  subject(:payload) { described_class.new(session, current_user: current_user).as_json }

  before_all do
    project.add_owner(user)
  end

  before do
    stub_licensed_features(project_level_compliance_dashboard: true)
    insert_ai_governance_sessions(session_row)
    clickhouse_fixture(:ai_audit_events, [
      audit_event_row(id: event_id, created_at: session_started_at + 1.minute),
      audit_event_row(created_at: session_started_at - 1.day - 1.minute),
      audit_event_row(created_at: session_started_at + 1.minute, ai_governance_session_id: non_existing_record_id)
    ])
  end

  def audit_event_row(created_at:, id: SecureRandom.uuid, ai_governance_session_id: session_row[:id])
    {
      id: id,
      event_name: 'run_tool',
      created_at: created_at,
      author_id: user.id,
      ip_address: '10.0.0.1',
      details: '{"tool":"bash"}',
      project_id: project.id,
      workflow_id: 0,
      ai_governance_session_id: ai_governance_session_id,
      traversal_path: project.project_namespace.traversal_path(with_organization: true)
    }
  end

  describe '#as_json' do
    it 'includes the session metadata', :aggregate_failures do
      expect(payload[:session]).to include(
        id: 21,
        source: 'claude_code_glab',
        agent_type: 'codex',
        flow_type: 'claude_code',
        project: { id: project.id, name: project.name, full_path: project.full_path }
      )
      expect(Time.zone.parse(payload[:session][:session_started_at])).to eq(session_started_at)
      expect(Time.zone.parse(payload[:session][:created_at])).to eq(session_started_at)
    end

    it 'includes only the audit events of the session within the clock skew window', :aggregate_failures do
      expect(payload[:audit_events]).to contain_exactly(
        hash_including(
          id: event_id,
          event_name: 'run_tool',
          author_id: user.id,
          ip_address: '10.0.0.1',
          details: { 'tool' => 'bash' }
        )
      )
      expect(Time.zone.parse(payload[:audit_events].first[:created_at])).to eq(session_started_at + 1.minute)
    end

    context 'when the session has no project' do
      let(:session) { super().merge('project_id' => nil) }

      it 'returns a nil project' do
        expect(payload[:session][:project]).to be_nil
      end
    end

    context 'when the user cannot read the project' do
      let(:current_user) { create(:user) }

      it 'returns a nil project' do
        expect(payload[:session][:project]).to be_nil
      end
    end

    context 'when the session timestamps are strings' do
      let(:session) { super().merge('created_at' => '2026-07-01T10:00:00Z') }

      it 'parses them' do
        expect(Time.zone.parse(payload[:session][:created_at])).to eq(session_started_at)
      end
    end

    context 'when the session timestamps are nil' do
      let(:session) { super().merge('session_started_at' => nil, 'created_at' => nil, 'updated_at' => nil) }

      it 'keeps nil values', :aggregate_failures do
        expect(payload[:session]).to include(session_started_at: nil, created_at: nil, updated_at: nil)
        expect(payload[:audit_events].pluck(:id)).to include(event_id)
      end
    end
  end
end
