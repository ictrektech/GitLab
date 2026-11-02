# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::FoundationalAgentsPresenter, feature_category: :duo_agent_platform do
  include_context 'with mocked Foundational Chat Agents'

  subject(:presenter) { described_class.new(group, current_user: user) }

  let(:references) { presenter.listed_statuses.pluck(:reference) }
  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }
  let(:orbit_enabled) { true }
  let(:ultimate) { true }

  let(:mocked_foundational_chat_agents) do
    [
      foundational_duo_chat_agent,
      foundational_chat_agent_1,
      { id: 3, reference: 'security_analyst_agent', version: 'v1', name: 'Security Analyst',
        description: 'Security agent', ultimate_only: true },
      { id: 4, reference: 'orbit_agent', version: 'v1', name: 'Orbit', description: 'Orbit agent' }
    ]
  end

  before do
    allow(::Analytics::KnowledgeGraph).to receive(:enabled_for?).with(user).and_return(orbit_enabled)
    allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(ultimate)
  end

  it 'lists every agent but Duo Chat' do
    expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'security_analyst_agent', 'orbit_agent')
  end

  context 'when Orbit is off for the user' do
    let(:orbit_enabled) { false }

    it 'hides the Orbit agent' do
      expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'security_analyst_agent')
    end
  end

  context 'without the Ultimate license' do
    let(:ultimate) { false }

    it 'hides the Ultimate-only agents' do
      expect(references).to contain_exactly(foundational_chat_agent_1_ref, 'orbit_agent')
    end
  end

  context 'for a subgroup' do
    let(:root_group) { build_stubbed(:group) }
    let(:group) { build_stubbed(:group, parent: root_group) }
    let(:root_statuses) { [{ reference: foundational_chat_agent_1_ref, name: 'Agent 1', enabled: false }] }

    before do
      allow(group).to receive(:root_ancestor).and_return(root_group)
      allow(root_group).to receive(:foundational_agents_statuses).and_return(root_statuses)
    end

    it 'lists the statuses of the top-level group' do
      expect(presenter.listed_statuses).to eq(root_statuses)
    end
  end
end
