# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Tracking::WorkflowIdentityPropertiesBuilder, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:workflow) do
    build(:duo_workflows_workflow, project: project, user: user, workflow_definition: workflow_definition,
      ai_catalog_item_version: ai_catalog_item_version)
  end

  let(:workflow_definition) { 'software_development' }
  let(:ai_catalog_item_version) { nil }

  subject(:to_h) { described_class.new(workflow).to_h }

  describe '#to_h' do
    context 'with a custom flow from the AI Catalog' do
      let_it_be(:item) { create(:ai_catalog_item, :flow) }
      let(:workflow_definition) { Ai::DuoWorkflows::Workflow::AI_CATALOG_AGENT_FLOW_TYPE }
      let(:ai_catalog_item_version) { item.latest_version }

      it 'returns the identity properties of the catalog item' do
        expect(to_h).to eq(
          item_type: 'custom_flow',
          item_version: item.latest_version.version,
          item_schema_version: item.latest_version.def_version,
          custom_item_id: item.id
        )
      end
    end

    context 'with a GitLab flow that has a catalog item' do
      let_it_be(:item) do
        create(:ai_catalog_item, :flow, :public,
          foundational_flow_reference: 'developer/v1',
          verification_level: :gitlab_maintained)
      end

      let(:workflow_definition) { 'developer/v1' }
      let(:ai_catalog_item_version) { item.latest_version }

      it 'returns the identity properties of the foundational flow' do
        expect(to_h).to eq(
          item_type: 'foundational_flow',
          item_version: '^3.0.0',
          item_schema_version: 'v1',
          flow_name: 'developer'
        )
      end
    end

    context 'with a GitLab flow that has no catalog item' do
      let(:workflow_definition) { 'developer/v1' }

      it 'returns the same identity properties as with a catalog item' do
        expect(to_h).to eq(
          item_type: 'foundational_flow',
          item_version: '^3.0.0',
          item_schema_version: 'v1',
          flow_name: 'developer'
        )
      end
    end

    context 'with a foundational agent' do
      let(:workflow_definition) { 'analytics_agent/v1' }

      it 'returns the identity properties of the agent' do
        expect(to_h).to eq(
          item_type: 'foundational_agent',
          item_version: '^2.0.0',
          item_schema_version: 'v1',
          flow_name: 'chat',
          component_name: 'analytics_agent'
        )
      end
    end

    context 'with a foundational agent from the AI Catalog' do
      # 348 is the global_catalog_id of the duo_planner foundational agent
      let(:item) { build(:ai_catalog_item, :agent, id: 348) }
      let(:workflow_definition) { Ai::DuoWorkflows::Workflow::AI_CATALOG_AGENT_FLOW_TYPE }
      let(:ai_catalog_item_version) { build(:ai_catalog_item_version, item: item) }

      before do
        stub_saas_features(gitlab_duo_saas_only: true)
      end

      it 'returns the identity properties of the agent' do
        expect(to_h).to eq(
          item_type: 'foundational_agent',
          item_schema_version: 'v1',
          flow_name: 'chat',
          component_name: 'duo_planner'
        )
      end
    end

    context 'with a workflow definition that is neither a flow nor an agent' do
      it 'returns no properties' do
        expect(to_h).to eq({})
      end
    end
  end
end
