# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::Concerns::WorkflowEventTracking, feature_category: :duo_agent_platform do
  let(:test_class) do
    Class.new do
      include Ai::DuoWorkflows::Concerns::WorkflowEventTracking

      public :track_workflow_event
    end
  end

  let(:instance) { test_class.new }

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, :with_namespace) }

  describe '#track_workflow_event' do
    subject(:track_workflow_event) { instance.track_workflow_event('agent_platform_session_created', workflow) }

    context 'with a project-level workflow' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

      it 'scopes the event to the project and its namespace' do
        expect { track_workflow_event }.to trigger_internal_events('agent_platform_session_created')
          .with(category: 'InternalEventTracking',
            user: user,
            project: project,
            namespace: project.namespace,
            additional_properties: {
              label: workflow.workflow_definition,
              value: workflow.id,
              property: workflow.environment
            }
          )
      end

      it 'adds additional properties to the event' do
        expect do
          instance.track_workflow_event('agent_platform_session_created', workflow,
            additional_properties: { mcp_client_name: 'claude-code' })
        end.to trigger_internal_events('agent_platform_session_created')
          .with(category: 'InternalEventTracking',
            user: user,
            project: project,
            namespace: project.namespace,
            additional_properties: {
              label: workflow.workflow_definition,
              value: workflow.id,
              property: workflow.environment,
              mcp_client_name: 'claude-code'
            }
          )
      end
    end

    context 'with a namespace-level workflow' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:workflow) { create(:duo_workflows_workflow, project: nil, namespace: subgroup, user: user) }

      %w[
        agent_platform_session_created
        agent_platform_session_started
        agent_platform_session_resumed
        agent_platform_session_stopped
        agent_platform_session_dropped
        agent_platform_session_finished
      ].each do |event_name|
        it "scopes #{event_name} to the workflow namespace" do
          expect { instance.track_workflow_event(event_name, workflow) }.to trigger_internal_events(event_name)
            .with(category: 'InternalEventTracking',
              user: user,
              project: nil,
              namespace: subgroup,
              additional_properties: {
                label: workflow.workflow_definition,
                value: workflow.id,
                property: workflow.environment
              }
            )
        end
      end

      it 'passes the workflow namespace to AiTracking' do
        expect(Gitlab::Tracking::AiTracking).to receive(:track_event)
          .with('agent_platform_session_created', hash_including(user: user, project: nil, namespace: subgroup))
          .and_call_original

        track_workflow_event
      end
    end
  end
end
