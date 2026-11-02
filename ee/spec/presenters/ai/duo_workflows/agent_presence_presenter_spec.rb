# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AgentPresencePresenter, feature_category: :duo_agent_platform do
  let(:project) { build_stubbed(:project) }
  let(:user) { build_stubbed(:user) }
  let(:workflow) { build_stubbed(:duo_workflows_workflow, project: project, user: user) }

  subject(:presenter) { described_class.new(workflow) }

  describe '#session_id' do
    it 'returns the workflow id' do
      expect(presenter.session_id).to eq(workflow.id)
    end
  end

  describe '#agent_catalog_web_path' do
    it 'is nil when the workflow has no catalog item' do
      expect(presenter.agent_catalog_web_path).to be_nil
    end

    context 'when the workflow runs a catalog agent' do
      let(:item) { build_stubbed(:ai_catalog_item, :agent) }
      let(:item_version) { build_stubbed(:ai_catalog_item_version, item: item) }
      let(:workflow) { build_stubbed(:duo_workflows_workflow, ai_catalog_item_version: item_version) }

      it 'returns the catalog page path of the agent' do
        expect(presenter.agent_catalog_web_path).to eq("/explore/ai-catalog/agents/#{item.id}")
      end
    end
  end
end
