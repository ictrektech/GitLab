# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::Governance::GroupSessionsResolver, :click_house,
  feature_category: :compliance_management do
  include GraphqlHelpers
  include Ai::Governance::SessionClickHouseHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:other_user) { create(:user) }
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) { create(:group_member, :guest, member_role: member_role, user: user, group: group) }
  let_it_be(:reference_time) { Time.current.change(usec: 0) }

  let(:duo_session_id) { 1 }
  let(:external_session_id) { 2 }
  let(:current_user) { user }
  let(:args) { {} }

  subject(:resolved) { resolve(described_class, obj: group, args: args, ctx: { current_user: current_user }) }

  before do
    stub_licensed_features(
      custom_roles: true,
      project_level_compliance_dashboard: true,
      group_level_compliance_dashboard: true
    )
    allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)

    insert_ai_governance_sessions(
      ai_governance_session_row(id: duo_session_id, namespace: project.project_namespace, project: project,
        user: user, flow_type: 'chat', session_started_at: reference_time - 2.hours),
      ai_governance_session_row(id: external_session_id, namespace: group, user: other_user,
        source: :claude_code_compliance_api, flow_type: 'claude_code', session_started_at: reference_time - 1.hour)
    )
  end

  def resolved_ids
    ai_governance_session_ids(resolved.items)
  end

  it 'returns the sessions of the group, newest first' do
    expect(resolved_ids).to eq([external_session_id, duo_session_id])
  end

  it 'passes a 180-day default window to the finder' do
    expect(::Ai::Governance::Sessions::ClickHouseFinder).to receive(:new)
      .with(hash_including(params: hash_including(session_started_after: be_within(1.minute).of(180.days.ago))))
      .and_call_original

    resolved
  end

  context 'with an id' do
    let(:args) { { id: ::Gitlab::GlobalId.build(model_name: 'Ai::Governance::Session', id: duo_session_id) } }

    it 'passes no default window to the finder' do
      expect(::Ai::Governance::Sessions::ClickHouseFinder).to receive(:new)
        .with(hash_including(params: hash_excluding(:session_started_after)))
        .and_call_original

      expect(resolved_ids).to eq([duo_session_id])
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(ai_governance_sessions_api: false)
    end

    it 'returns no sessions' do
      expect(resolved).to be_empty
    end
  end

  context 'when ClickHouse is not enabled for analytics' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
    end

    let_it_be(:pg_duo_session) do
      create(:ai_governance_session, namespace: project.project_namespace, project: project, user: user,
        flow_type: 'chat', session_started_at: reference_time - 2.hours)
    end

    let_it_be(:pg_external_session) do
      create(:ai_governance_session, :external, namespace: group, user: other_user,
        session_started_at: reference_time - 1.hour)
    end

    it 'returns the sessions from PostgreSQL, newest first, with offset pagination', :aggregate_failures do
      expect(::Ai::Governance::Sessions::ClickHouseFinder).not_to receive(:new)

      expect(resolved).to be_a(::Gitlab::Graphql::Pagination::OffsetActiveRecordRelationConnection)
      expect(resolved.to_a).to eq([pg_external_session, pg_duo_session])
    end

    context 'with filters' do
      let(:args) do
        { agent_class: 'INTERNAL_DAP', flow_type: 'chat', project_path: project.full_path,
          triggered_by_user_id: global_id_of(user), not: { triggered_by_user_id: global_id_of(other_user) } }
      end

      it 'passes them to the PostgreSQL finder' do
        expect(::Ai::Governance::SessionsFinder).to receive(:new).with(
          current_user: current_user,
          namespace: group,
          params: {
            agent_class: :internal_dap, flow_type: 'chat', project_path: project.full_path, user_id: user.id,
            session_started_after: be_within(1.minute).of(180.days.ago), not: { user_id: other_user.id }
          }
        ).and_call_original

        expect(resolved.to_a).to eq([pg_duo_session])
      end
    end

    context 'with an id filter' do
      let(:args) { { id: pg_external_session.to_global_id } }

      it 'returns only that session' do
        expect(resolved.to_a).to eq([pg_external_session])
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_sessions_api: false)
      end

      it 'returns no sessions' do
        expect(::Ai::Governance::SessionsFinder).not_to receive(:new)

        expect(resolved).to be_empty
      end
    end
  end

  context 'when the user cannot read agent artifacts' do
    let(:current_user) { create(:user) }

    it 'returns no sessions' do
      expect(resolved_ids).to be_empty
    end
  end

  describe 'agent class' do
    using RSpec::Parameterized::TableSyntax

    where(:agent_class, :expected_ids) do
      'ALL'          | [2, 1]
      'INTERNAL_DAP' | [1]
      'EXTERNAL'     | [2]
    end

    with_them do
      let(:args) { { agent_class: agent_class } }

      it 'filters on the session source' do
        expect(resolved_ids).to eq(expected_ids)
      end
    end
  end

  context 'with a flow type filter' do
    let(:args) { { flow_type: 'chat' } }

    it 'returns matching sessions' do
      expect(resolved_ids).to eq([duo_session_id])
    end
  end

  context 'with a project path filter' do
    let(:args) { { project_path: project.full_path } }

    it 'returns the sessions of the project' do
      expect(resolved_ids).to eq([duo_session_id])
    end
  end

  context 'with a triggered by user filter' do
    let(:args) { { triggered_by_user_id: global_id_of(other_user) } }

    it 'returns sessions triggered by the user' do
      expect(resolved_ids).to eq([external_session_id])
    end
  end

  context 'with a session start range' do
    let(:args) do
      { session_started_after: reference_time - 3.hours, session_started_before: reference_time - 90.minutes }
    end

    it 'returns sessions started within the range' do
      expect(resolved_ids).to eq([duo_session_id])
    end
  end

  context 'when sessionStartedAfter equals sessionStartedBefore' do
    let(:args) { { session_started_after: reference_time - 1.hour, session_started_before: reference_time - 1.hour } }

    it 'returns sessions started at that time' do
      expect(resolved_ids).to eq([external_session_id])
    end
  end

  context 'when sessionStartedAfter is after sessionStartedBefore' do
    let(:args) { { session_started_after: reference_time, session_started_before: reference_time - 1.hour } }

    it 'returns an argument error' do
      expect(resolved).to be_a(Gitlab::Graphql::Errors::ArgumentError)
      expect(resolved.message).to eq('sessionStartedAfter must not be after sessionStartedBefore')
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_sessions_api: false)
      end

      it 'returns an argument error' do
        expect(resolved).to be_a(Gitlab::Graphql::Errors::ArgumentError)
      end
    end
  end

  describe 'negated filters' do
    using RSpec::Parameterized::TableSyntax

    where(:not_args, :expected_ids) do
      { flow_type: 'chat' }              | [2]
      { project_path: 'does/not-exist' } | [2, 1]
      {}                                 | [2, 1]
    end

    with_them do
      let(:args) { { not: not_args } }

      it 'excludes matching sessions' do
        expect(resolved_ids).to eq(expected_ids)
      end
    end

    context 'with a negated project path' do
      let(:args) { { not: { project_path: project.full_path } } }

      it 'excludes the project but keeps namespace-scoped sessions' do
        expect(resolved_ids).to eq([external_session_id])
      end
    end

    context 'with a negated triggered by user' do
      let(:args) { { not: { triggered_by_user_id: global_id_of(other_user) } } }

      it 'passes the unwrapped user id to the finder' do
        expect(::Ai::Governance::Sessions::ClickHouseFinder).to receive(:new)
          .with(hash_including(params: hash_including(not: { user_id: other_user.id })))
          .and_call_original

        expect(resolved_ids).to eq([duo_session_id])
      end
    end
  end
end
