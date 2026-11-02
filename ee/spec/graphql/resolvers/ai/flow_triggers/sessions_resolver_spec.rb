# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::FlowTriggers::SessionsResolver, feature_category: :dap_triggers do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project) }

  let_it_be(:older_session) do
    create(:duo_workflows_workflow, :finished, project: project, environment: :web, goal: 'Fix the pipeline',
      created_at: 3.days.ago, trigger_flow_trigger: flow_trigger, service_account: flow_trigger.service_account)
  end

  let_it_be(:newer_session) do
    create(:duo_workflows_workflow, :failed, project: project, environment: :web, goal: 'Update the docs',
      created_at: 1.day.ago, trigger_flow_trigger: flow_trigger, service_account: flow_trigger.service_account)
  end

  let(:args) { {} }

  let(:connection) { resolve(described_class, obj: flow_trigger, args: args, ctx: { current_user: user }) }

  subject(:sessions) { connection.items.to_a }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(true)
  end

  it 'returns the sessions newest first with keyset pagination' do
    expect(sessions).to eq([newer_session, older_session])
    expect(connection).to be_a(::Gitlab::Graphql::Pagination::Keyset::Connection)
  end

  context 'with sort' do
    let(:args) { { sort: :created_asc } }

    it { is_expected.to eq([older_session, newer_session]) }
  end

  context 'with a status sort' do
    let(:args) { { sort: 'STATUS_DESC' } }

    it 'uses offset pagination' do
      expect(sessions).to eq([newer_session, older_session])
      expect(connection).to be_a(::Gitlab::Graphql::Pagination::OffsetActiveRecordRelationConnection)
    end
  end

  context 'with statuses' do
    let(:args) { { statuses: [::Ai::DuoWorkflows::Workflow.state_machine.states[:failed].value] } }

    it { is_expected.to eq([newer_session]) }
  end

  context 'with search' do
    let(:args) { { search: 'pipeline' } }

    it { is_expected.to eq([older_session]) }
  end

  context 'with created_after' do
    let(:args) { { created_after: 2.days.ago } }

    it { is_expected.to eq([newer_session]) }
  end

  context 'with created_before' do
    let(:args) { { created_before: 2.days.ago } }

    it { is_expected.to eq([older_session]) }
  end

  it 'returns no sessions for a group flow trigger' do
    group_trigger = build_stubbed(:ai_flow_trigger, project: nil, group: build_stubbed(:group),
      user: create(:service_account))
    create(:duo_workflows_workflow, user: user, trigger_flow_trigger_id: group_trigger.id,
      service_account: group_trigger.user)

    expect(resolve(described_class, obj: group_trigger, ctx: { current_user: user }).items).to be_empty
  end
end
