# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AgentPresenceEntity, feature_category: :duo_agent_platform do
  let(:project) { build_stubbed(:project) }
  let(:user) { build_stubbed(:user) }
  let(:current_user) { build_stubbed(:user) }
  let(:item) { build_stubbed(:ai_catalog_item, :agent, name: 'Developer Agent') }
  let(:item_version) { build_stubbed(:ai_catalog_item_version, item: item) }
  let(:workflow) do
    build_stubbed(:duo_workflows_workflow, project: project, user: user, ai_catalog_item_version: item_version,
      source_type: :slack, source_link: 'https://slack.com/archives/C123/p456', trigger_source: :scheduled)
  end

  let(:can_read_session) { true }
  let(:request) { EntityRequest.new(current_user: current_user) }
  let(:presenter) { ::Ai::DuoWorkflows::AgentPresencePresenter.new(workflow) }

  subject(:json) { described_class.new(presenter, request: request).as_json.deep_symbolize_keys }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?)
      .with(current_user, :read_duo_workflow, workflow).and_return(can_read_session)
  end

  it 'exposes the actor line data' do
    expect(json).to match(
      session_id: workflow.id,
      agent_name: 'Developer Agent',
      agent_catalog_web_path: "/explore/ai-catalog/agents/#{item.id}",
      source_type: 'SLACK',
      source_link: 'https://slack.com/archives/C123/p456',
      trigger_source: 'SCHEDULED',
      user: a_hash_including(id: user.id, username: user.username, web_path: "/#{user.username}"),
      user_permissions: { read_duo_workflow: true }
    )
  end

  context 'when the viewer cannot read the session' do
    let(:can_read_session) { false }

    it 'still exposes the presence but hides the source link' do
      expect(json).to include(
        session_id: workflow.id,
        agent_name: 'Developer Agent',
        source_type: 'SLACK',
        source_link: nil,
        trigger_source: 'SCHEDULED',
        user_permissions: { read_duo_workflow: false }
      )
    end
  end

  context 'when the session has no catalog agent or recorded source' do
    let(:workflow) { build_stubbed(:duo_workflows_workflow, project: project, user: user) }

    it 'returns null for the optional fields' do
      expect(json).to include(agent_catalog_web_path: nil, source_type: nil, source_link: nil)
    end
  end
end
