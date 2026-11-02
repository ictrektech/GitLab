# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionType, feature_category: :compliance_management do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('AiGovernanceSession') }

  it 'limits count to 1000 by default' do
    limit = described_class.connection_type.fields['count'].arguments['limit']

    expect(limit.default_value).to eq(1000)
  end

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :id, :session_id, :flow_type, :agent_type, :source, :session_started_at, :web_path, :download_path, :project,
      :triggered_by, :audit_events, :audit_events_count, :merge_request_links, :note_links, :work_item_links
    )
  end

  it 'types the non-null fields', :aggregate_failures do
    expect(described_class.fields['id'].type.to_type_signature).to eq('AiGovernanceSessionID!')
    expect(described_class.fields['source'].type.to_type_signature).to eq('AiGovernanceSessionSource!')
    expect(described_class.fields['sessionStartedAt'].type.to_type_signature).to eq('Time!')
  end

  it 'types the link fields', :aggregate_failures do
    expect(described_class.fields['mergeRequestLinks'].type.to_type_signature)
      .to eq('AiGovernanceSessionMergeRequestLinkConnection')
    expect(described_class.fields['noteLinks'].type.to_type_signature).to eq('AiGovernanceSessionNoteLinkConnection')
    expect(described_class.fields['workItemLinks'].type.to_type_signature)
      .to eq('AiGovernanceSessionWorkItemLinkConnection')
  end

  describe 'field resolution' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user) }

    let(:duo_row) do
      { 'id' => 7, 'source' => 0, 'workflow_id' => 42, 'external_xid' => nil, 'project_id' => project.id,
        'namespace_id' => project.project_namespace_id, 'user_id' => user.id, 'flow_type' => 'chat',
        'agent_type' => nil, 'session_started_at' => '2026-07-01 10:00:00.000000' }
    end

    let(:external_row) do
      duo_row.merge('source' => 2, 'workflow_id' => nil, 'external_xid' => 'glab_123', 'agent_type' => 'claude-code')
    end

    it 'builds the global ID from the row id' do
      expect(resolve_field(:id, duo_row)).to eq(::Gitlab::GlobalId.build(model_name: 'Ai::Governance::Session', id: 7))
    end

    it 'maps the source value to its name', :aggregate_failures do
      expect(resolve_field(:source, duo_row)).to eq('gitlab_duo')
      expect(resolve_field(:source, external_row)).to eq('claude_code_glab')
    end

    it 'maps the source of an ActiveRecord session', :aggregate_failures do
      expect(resolve_field(:source, build(:ai_governance_session))).to eq('gitlab_duo')
      expect(resolve_field(:source, build(:ai_governance_session, :external, source: :claude_code_glab)))
        .to eq('claude_code_glab')
    end

    it 'parses the session start time' do
      expect(resolve_field(:session_started_at, duo_row)).to eq(Time.utc(2026, 7, 1, 10))
    end

    it 'returns the workflow ID as the session ID for a GitLab Duo session' do
      expect(resolve_field(:session_id, duo_row)).to eq('42')
    end

    it 'returns the external ID as the session ID for a session from another source' do
      expect(resolve_field(:session_id, external_row)).to eq('glab_123')
    end

    it 'returns no audit events for a GitLab Duo session without a workflow' do
      expect(resolve_field(:audit_events, duo_row.merge('workflow_id' => nil)).items).to be_empty
    end

    it 'counts no audit events for a GitLab Duo session without a workflow' do
      expect(resolve_field(:audit_events_count, duo_row.merge('workflow_id' => nil))).to eq(0)
    end

    it 'looks up the audit events of a session from another source by session ID' do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

      expect(::AuditEvents::AiAuditEvents::ClickHouseFinder).to receive(:new)
        .with(ai_governance_session_id: 7,
          created_after: Time.utc(2026, 7, 1, 10) - ::Ai::Governance::Session::AUDIT_EVENTS_CLOCK_SKEW)
        .and_call_original

      resolve_field(:audit_events, external_row)
    end

    context 'when ClickHouse is not enabled for analytics' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it 'looks up the audit events of a session from another source in PostgreSQL' do
        expect(::AuditEvents::AiAuditEvents::PostgresqlFinder).to receive(:new)
          .with(ai_governance_session_id: 7,
            created_after: Time.utc(2026, 7, 1, 10) - ::Ai::Governance::Session::AUDIT_EVENTS_CLOCK_SKEW)
          .and_call_original
        expect(::AuditEvents::AiAuditEvents::ClickHouseFinder).not_to receive(:new)

        resolve_field(:audit_events, external_row)
      end

      describe 'audit events count' do
        let_it_be(:started_at) { Time.current.change(usec: 0) - 1.hour }
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }
        let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

        let_it_be(:duo_session) do
          create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
            workflow_id: workflow.id, session_started_at: started_at)
        end

        let_it_be(:other_duo_session) do
          create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
            workflow_id: other_workflow.id, session_started_at: started_at)
        end

        let_it_be(:external_session) do
          create(:ai_governance_session, :external, namespace: project.project_namespace, user: user,
            session_started_at: started_at)
        end

        let_it_be(:other_external_session) do
          create(:ai_governance_session, :external, namespace: project.project_namespace, user: user,
            session_started_at: started_at)
        end

        before_all do
          create_list(:audit_events_ai_audit_event, 2, workflow_id: workflow.id, created_at: started_at + 1.minute)
          create(:audit_events_ai_audit_event, workflow_id: other_workflow.id, created_at: started_at + 1.minute)
          create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: external_session.id,
            created_at: started_at + 1.minute)
          create(:audit_events_ai_audit_event, workflow_id: nil, ai_governance_session_id: external_session.id,
            created_at: started_at - 1.day - 1.minute)
        end

        def resolved_audit_events(session)
          batch_sync { resolve_field(:audit_events, session) }.items
        end

        it 'matches the audit events of a GitLab Duo session and an external session', :aggregate_failures do
          [duo_session, external_session].each do |session|
            count = batch_sync { resolve_field(:audit_events_count, session) }

            expect(count).to be_positive
            expect(count).to eq(resolved_audit_events(session).count)
          end
        end

        it 'counts a page of sessions with one query per session kind', :aggregate_failures do
          sessions = [duo_session, other_duo_session, external_session, other_external_session]
          counts = nil

          recorder = ActiveRecord::QueryRecorder.new do
            counts = batch_sync { sessions.map { |session| resolve_field(:audit_events_count, session) } }
          end

          expect(counts).to eq([2, 1, 1, 0])
          expect(recorder.log.grep(/\bCOUNT\(\*\).*FROM "ai_audit_events"/).size).to eq(2)
        end
      end
    end

    it 'returns no web path for a session from another source' do
      expect(resolve_field(:web_path, external_row)).to be_nil
    end

    context 'when ClickHouse is enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      end

      it 'returns the session download path for a project session from another source' do
        expect(batch_sync { resolve_field(:download_path, external_row) })
          .to eq(::Gitlab::Routing.url_helpers.download_session_project_security_agent_artifact_path(project, 7))
      end

      it 'returns the session download path for a namespace session from another source' do
        group = create(:group)
        row = external_row.merge('project_id' => nil, 'namespace_id' => group.id)

        expect(batch_sync { resolve_field(:download_path, row) })
          .to eq(::Gitlab::Routing.url_helpers.download_session_group_security_agent_artifact_path(group, 7))
      end
    end

    it 'returns the workflow download path for a GitLab Duo session' do
      expect(batch_sync { resolve_field(:download_path, duo_row) })
        .to eq(::Gitlab::Routing.url_helpers.download_project_security_agent_artifact_path(project, 42))
    end

    it 'returns no download path for a GitLab Duo session without a workflow' do
      expect(resolve_field(:download_path, duo_row.merge('workflow_id' => nil))).to be_nil
    end

    context 'when ClickHouse is not enabled' do
      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      end

      it 'returns no download path for a session from another source' do
        expect(resolve_field(:download_path, external_row)).to be_nil
      end

      it 'returns the workflow download path for a GitLab Duo session' do
        expect(batch_sync { resolve_field(:download_path, duo_row) })
          .to eq(::Gitlab::Routing.url_helpers.download_project_security_agent_artifact_path(project, 42))
      end
    end
  end

  it 'exposes a countable connection' do
    expect(described_class.connection_type.fields.keys).to include('count')
  end

  describe 'connection count on the PostgreSQL path' do
    let_it_be(:group) { create(:group) }
    let_it_be(:sessions) { create_list(:ai_governance_session, 3, namespace: group) }

    # The paginated items match nothing, so a non-zero count can only come from `count_relation`.
    let(:items) do
      count_relation = ::Ai::Governance::Session.for_namespace(group.id)

      ::Gitlab::Graphql::Pagination::OffsetPaginatedRelation.new(::Ai::Governance::Session.none).tap do |relation|
        relation.define_singleton_method(:count_relation) { count_relation }
      end
    end

    let(:connection) do
      described_class::SessionConnectionType.scoped_new(
        ::Gitlab::Graphql::Pagination::OffsetActiveRecordRelationConnection.new(items),
        query_context(user: nil)
      )
    end

    it 'counts the count relation' do
      expect(connection.count(limit: 1000)).to eq(3)
    end

    it 'returns limit + 1 when the count exceeds the limit' do
      expect(connection.count(limit: 1)).to eq(2)
    end

    context 'when the items have no count relation' do
      let(:items) { ::Ai::Governance::Session.for_namespace(group.id) }

      it 'counts the items' do
        expect(connection.count(limit: 1000)).to eq(3)
      end
    end
  end
end
