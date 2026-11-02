# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::WorkItems::Instrumentation::TrackingService, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, developers: user) }
  let_it_be(:work_item) { create(:work_item, project: project) }

  let(:service) { described_class.new(**service_params) }
  let(:service_params) { base_params.merge(additional_params) }
  let(:base_params) { { work_item: work_item, current_user: user } }

  describe '#execute', :clean_gitlab_redis_shared_state do
    context 'when extra_properties are provided' do
      let(:additional_params) do
        {
          event: ::Gitlab::WorkItems::Instrumentation::EventActions::AGENT_PLAN_CREATE,
          extra_properties: { source: 'ai_workflows', work_item_id: work_item.id }
        }
      end

      let(:expected_properties_with_extras) do
        {
          user: user,
          project: project,
          namespace: project.project_namespace,
          additional_properties: {
            label: work_item.work_item_type.name,
            property: "Developer",
            source: 'ai_workflows',
            work_item_id: work_item.id
          }
        }
      end

      it 'merges them into additional_properties' do
        expect { service.execute }
          .to trigger_internal_events('work_item_agent_plan_create')
          .with(expected_properties_with_extras)
      end
    end
  end

  describe '.track_decision_event' do
    let_it_be(:decision) { create(:work_item_decision, work_item: work_item) }

    let(:extra_properties) { {} }

    subject(:track) do
      described_class.track_decision_event(
        event: ::Gitlab::WorkItems::Instrumentation::EventActions::DECISION_RESOLVE,
        decision: decision,
        current_user: user,
        extra_properties: extra_properties
      )
    end

    it 'tracks the event against the decision and its work item' do
      expect { track }.to trigger_internal_events('work_item_decision_resolve').with(
        user: user,
        project: project,
        namespace: project.project_namespace,
        additional_properties: {
          label: work_item.work_item_type.name,
          property: 'Developer',
          source: 'internal',
          work_item_id: work_item.id,
          decision_id: decision.id
        }
      )
    end

    context 'with extra properties' do
      let(:extra_properties) { { resolution_type: 'write_in', value: 1 } }

      it 'merges them into the additional properties' do
        expect { track }.to trigger_internal_events('work_item_decision_resolve').with(
          user: user,
          project: project,
          namespace: project.project_namespace,
          additional_properties: {
            label: work_item.work_item_type.name,
            property: 'Developer',
            source: 'internal',
            work_item_id: work_item.id,
            decision_id: decision.id,
            resolution_type: 'write_in',
            value: 1
          }
        )
      end
    end
  end
end
