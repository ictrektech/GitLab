# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::FlowTriggerType, feature_category: :dap_triggers do
  include GraphqlHelpers

  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiFlowTriggerType')
  end

  it 'has the expected fields' do
    expected_fields = %w[
      id
      active
      description
      event_types
      config_path
      config_url
      group
      project
      user
      ai_catalog_item_consumer
      created_at
      updated_at
      filter
      precondition
      goals
      status_on_finish
      ready_merge_requests_on_finish
      flow_schedules
      last_run
      running_count
      run_stats
      sessions
    ]

    expect(described_class.own_fields.size).to eq(expected_fields.size)
    expect(described_class).to include_graphql_fields(*expected_fields)
  end

  it { expect(described_class).to require_graphql_authorizations(:read_ai_flow_triggers) }

  describe 'container fields' do
    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    context 'when flow trigger belongs to a group' do
      let_it_be(:flow_trigger) { create(:ai_flow_trigger, :for_inheritance_consumer) }

      it 'returns the group and no project' do
        expect(batch_sync { resolve_field(:group, flow_trigger) }).to eq(flow_trigger.group)
        expect(resolve_field(:project, flow_trigger)).to be_nil
      end
    end

    context 'when flow trigger belongs to a project' do
      let_it_be(:flow_trigger) { create(:ai_flow_trigger) }

      it 'returns the project and no group' do
        expect(resolve_field(:project, flow_trigger)).to eq(flow_trigger.project)
        expect(resolve_field(:group, flow_trigger)).to be_nil
      end
    end
  end

  describe '#precondition' do
    before do
      allow(described_class).to receive(:authorized?).and_return(true)
    end

    context 'when flow trigger has a foundational flow with a precondition' do
      let_it_be(:project) { create(:project, :in_group) }
      let_it_be(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'fix_pipeline/v1') }
      let_it_be(:item_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project:, item:) }
      let_it_be(:flow_trigger) do
        create(:ai_flow_trigger,
          :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: item_consumer,
          event_types: [::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
      end

      it 'returns the precondition from the foundational flow' do
        expect(resolve_field(:precondition, flow_trigger)).to eq(
          ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1.precondition
        )
      end
    end

    context 'when flow trigger has no item consumer' do
      let_it_be(:flow_trigger) { create(:ai_flow_trigger) }

      it 'returns nil' do
        expect(resolve_field(:precondition, flow_trigger)).to be_nil
      end
    end
  end
end
