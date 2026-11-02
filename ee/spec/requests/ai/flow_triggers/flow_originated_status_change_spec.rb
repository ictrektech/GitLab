# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Work item status change flow triggers', :request_store, feature_category: :dap_triggers do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:human) { create(:user, maintainer_of: project) }
  let_it_be(:flow_service_account) do
    create(:user, :service_account, composite_identity_enforced: true, developer_of: project,
      provisioned_by_group: group)
  end

  let_it_be(:trigger_service_account) { create(:service_account, developer_of: project) }
  let_it_be(:status_trigger) do
    create(:ai_flow_trigger, project: project, user: trigger_service_account,
      event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]])
  end

  let_it_be(:flow_token) do
    create(:oauth_access_token,
      organization: project.organization,
      application: create(:doorkeeper_application),
      resource_owner: flow_service_account,
      expires_in: 1.hour,
      scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ["user:#{human.id}"])
  end

  let_it_be_with_reload(:work_item) { create(:work_item, :issue, project: project) }

  let(:worker_class) { ::Ai::Catalog::Flows::ExecuteWorkItemStatusChangedWorkflowTriggersWorker }
  let(:status) { build(:work_item_system_defined_status, :in_progress) }
  let(:mutation) do
    graphql_mutation(:workItemUpdate,
      { 'id' => work_item.to_global_id.to_s, 'statusWidget' => { 'status' => status.to_gid.to_s } },
      'workItem { id } errors')
  end

  let(:run_service) { instance_double(::Ai::FlowTriggers::RunService, execute: nil) }

  before do
    stub_licensed_features(work_item_status: true)
    allow(::Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
  end

  # Runs the queued job the way Sidekiq does, including the identity restore middleware.
  def change_status_and_run_trigger_worker(token: {}, current_user: nil, headers: {})
    worker_class.clear
    post_graphql(mutation.query, variables: mutation.variables, token: token, current_user: current_user,
      headers: headers)

    expect(graphql_mutation_response(:work_item_update)['errors']).to be_empty

    job = worker_class.jobs.last
    ::Gitlab::SafeRequestStore.clear!
    ::Gitlab::Auth::Identity.sidekiq_restore!(job)
    worker_class.new.perform(*job['args'])
  end

  context 'when a flow changes the status with its composite identity token' do
    context 'when ai_flow_trigger_chaining is disabled' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
      end

      it 'does not start status-triggered flows' do
        expect(::Ai::FlowTriggers::RunService).not_to receive(:new)

        change_status_and_run_trigger_worker(token: { oauth_access_token: flow_token })
      end
    end

    context 'when ai_flow_trigger_chaining is enabled' do
      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: human) }

      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(human, :update_duo_workflow, parent_workflow).and_return(true)
      end

      it 'starts status-triggered flows as children of the workflow in the header' do
        expect(::Ai::FlowTriggers::RunService).to receive(:new)
          .with(hash_including(current_user: human, flow_trigger: status_trigger, parent_workflow: parent_workflow))
          .and_return(run_service)
        expect(run_service).to receive(:execute)

        change_status_and_run_trigger_worker(token: { oauth_access_token: flow_token },
          headers: { 'X-Gitlab-Duo-Workflow-Id' => parent_workflow.id.to_s })
      end

      context 'without the workflow header' do
        it 'does not start status-triggered flows' do
          expect(::Ai::FlowTriggers::RunService).not_to receive(:new)

          change_status_and_run_trigger_worker(token: { oauth_access_token: flow_token })
        end
      end
    end
  end

  context 'when a human changes the status' do
    it 'starts status-triggered flows' do
      expect(::Ai::FlowTriggers::RunService).to receive(:new)
        .with(hash_including(current_user: human, flow_trigger: status_trigger)).and_return(run_service)
      expect(run_service).to receive(:execute)

      change_status_and_run_trigger_worker(current_user: human)
    end
  end
end
