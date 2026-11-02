# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Pipelines::HookService, feature_category: :continuous_integration do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:pipeline) { create(:ci_pipeline, :created, project: project, user: user) }

  subject(:service) { described_class.new(pipeline) }

  describe '#execute' do
    def expect_flow_trigger_service_with_hook_data
      trigger_service = instance_double(Ai::FlowTriggers::EventTriggerService)

      expect(Ai::FlowTriggers::EventTriggerService).to receive(:new).with(
        project: project,
        current_user: user,
        event: described_class::HOOK_NAME,
        data: satisfy { |data| data.to_h == hook_data }
      ).and_return(trigger_service)
      expect(trigger_service).to receive(:execute)
    end

    let(:hook_data) { { object_kind: 'pipeline' } }
    let(:pipeline_source) { :push }

    before do
      allow(Gitlab::DataBuilder::Pipeline).to receive(:build).with(pipeline).and_return(hook_data)
      allow(pipeline).to receive(:source).and_return(pipeline_source)
    end

    it 'executes flow triggers' do
      expect_flow_trigger_service_with_hook_data

      service.execute
    end

    context 'when the project has no hooks, integrations, or flow triggers' do
      context 'when the user can trigger flows' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(user, :trigger_ai_flow, project).and_return(true)
        end

        it 'does not build the hook data' do
          expect(Ai::FlowTrigger).to receive(:applicable_to_project).and_call_original
          expect(Gitlab::DataBuilder::Pipeline).not_to receive(:build)

          service.execute
        end
      end

      context 'when the user cannot trigger flows' do
        it 'does not build the hook data' do
          expect(Gitlab::DataBuilder::Pipeline).not_to receive(:build)

          service.execute
        end
      end
    end

    context 'with real flow triggers and a project hook' do
      let(:pipeline_source) { 'push' }

      let_it_be(:hook) { create(:project_hook, project: project, pipeline_events: true) }

      let_it_be(:matching_trigger) { create_pipeline_flow_trigger(source: 'push') }
      let_it_be(:filtered_out_trigger) { create_pipeline_flow_trigger(source: 'schedule') }

      def create_pipeline_flow_trigger(source:)
        create(:ai_flow_trigger, project: project,
          event_types: [Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]],
          filter: {
            described_class::HOOK_NAME.to_s => {
              'rules' => [{ 'field' => 'object_attributes.source', 'operator' => 'eq', 'value' => source }]
            }
          })
      end

      before do
        allow(Gitlab::DataBuilder::Pipeline).to receive(:build).and_call_original
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :trigger_ai_flow, project).and_return(true)
      end

      it 'builds the payload once and runs only the matching trigger with it', :aggregate_failures do
        run_service = instance_double(Ai::FlowTriggers::RunService)

        expect(Gitlab::DataBuilder::Pipeline).to receive(:build).with(pipeline).once.and_call_original
        expect(Ai::FlowTriggers::RunService).to receive(:new)
          .with(project: project, current_user: user, flow_trigger: matching_trigger, resource: pipeline)
          .and_return(run_service)
        expect(run_service).to receive(:execute) do |params|
          expect(params[:event]).to eq(described_class::HOOK_NAME)
          expect(Gitlab::Json::SafeParser.parse(params[:input])).to include(
            'object_kind' => 'pipeline',
            'object_attributes' => include('id' => pipeline.id, 'source' => 'push')
          )
        end

        service.execute
      end
    end

    ::Enums::Ci::Pipeline.gitlab_controlled_sources.each_key do |source|
      context "when pipeline is triggered by #{source}" do
        let(:pipeline_source) { source }

        it 'does not trigger AI Flows' do
          expect(Ai::FlowTriggers::EventTriggerService).not_to receive(:new)

          service.execute
        end
      end
    end

    context 'when project has active hooks' do
      let!(:hook) { create(:project_hook, project: project, pipeline_events: true) }

      it 'calls both parent execute and the flow trigger service' do
        expect(pipeline.project).to receive(:execute_hooks).with(hook_data, described_class::HOOK_NAME)
        expect_flow_trigger_service_with_hook_data

        service.execute
      end
    end
  end
end
