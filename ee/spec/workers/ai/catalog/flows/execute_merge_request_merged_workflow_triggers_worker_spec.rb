# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ExecuteMergeRequestMergedWorkflowTriggersWorker,
  feature_category: :dap_triggers do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, target_project: project)
  end

  let_it_be(:service_account) { create(:service_account) }
  let_it_be(:flow_trigger) do
    create(:ai_flow_trigger,
      project: project,
      user: service_account,
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
      filter: {
        'merge_request' => {
          'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => %w[merged] }]
        }
      }
    )
  end

  let_it_be(:developer_flow_session) do
    create(:duo_workflows_workflow,
      project: project,
      user: merge_request.author,
      merge_request: merge_request,
      workflow_definition: ::Ai::Catalog::FoundationalFlow.developer_v1.reference)
  end

  let(:cloud_event) do
    MergeRequests::MergedCloudEvent.build(merge_request: merge_request, current_user: user)
  end

  let(:resource) { merge_request }
  let(:event) { cloud_event }

  let(:wrong_event) do
    MergeRequests::MergedEvent.new(data: { merge_request_id: merge_request.id })
  end

  let(:doomed_resource) do
    create(:merge_request, source_project: project, target_project: project, source_branch: 'doomed-branch').tap do |mr|
      create(:duo_workflows_workflow,
        project: project,
        user: user,
        merge_request: mr,
        workflow_definition: ::Ai::Catalog::FoundationalFlow.developer_v1.reference)
    end
  end

  let(:doomed_resource_event) do
    MergeRequests::MergedCloudEvent.build(merge_request: doomed_resource, current_user: user)
  end

  it_behaves_like 'subscribes to event'
  it_behaves_like 'a cloud events flow trigger worker' do
    let(:additional_run_params) { { session_ids: [developer_flow_session.id] } }
    let(:current_user) { merge_request.author }
  end

  describe '#handle_event' do
    subject(:handle_event) { described_class.new.handle_event(cloud_event) }

    let(:run_service) { instance_double(Ai::FlowTriggers::RunService, execute: nil) }
    let(:filter_evaluator) { instance_double(Ai::FlowTriggers::FilterEvaluator, allowed?: true) }

    before do
      allow(Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_return(filter_evaluator)
      allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
    end

    it 'starts the flow as the author of the merge request', :aggregate_failures do
      expect(merge_request.author).not_to eq(user)

      expect(Ai::FlowTriggers::FilterEvaluator).to receive(:new).with(
        flow_trigger: flow_trigger,
        hook_scope: :merge_request,
        data: { 'action' => 'merged' }
      ).and_return(filter_evaluator)
      expect(Ai::FlowTriggers::RunService).to receive(:new).with(
        project: project,
        current_user: merge_request.author,
        flow_trigger: flow_trigger,
        resource: merge_request,
        parent_workflow: nil
      ).and_return(run_service)
      expect(run_service).to receive(:execute).with(
        {
          input: merge_request.iid.to_s,
          event: :merge_request,
          action: 'merged',
          session_ids: [developer_flow_session.id]
        }
      )

      handle_event
    end

    context 'when the merge_request_merged_flow_trigger feature flag is disabled for the project' do
      before do
        stub_feature_flags(merge_request_merged_flow_trigger: false)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the merge_request_merged_memory_distillation feature flag is disabled for the project' do
      before do
        stub_feature_flags(merge_request_merged_memory_distillation: false)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end
    end

    context 'when the merge request was created by a developer session' do
      let_it_be(:creator_merge_request) do
        create(:merge_request, :unique_branches, source_project: project, target_project: project)
      end

      let_it_be(:creator_session) do
        create(:duo_workflows_workflow,
          project: project,
          user: creator_merge_request.author,
          workflow_definition: ::Ai::Catalog::FoundationalFlow.developer_v1.reference)
      end

      let_it_be(:creator_link) do
        create(:duo_workflows_workflow_merge_request,
          workflow: creator_session,
          merge_request: creator_merge_request,
          project: project,
          link_type: :created)
      end

      let(:cloud_event) do
        MergeRequests::MergedCloudEvent.build(merge_request: creator_merge_request, current_user: user)
      end

      it 'includes the creator session id' do
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          project: project,
          current_user: creator_merge_request.author,
          flow_trigger: flow_trigger,
          resource: creator_merge_request,
          parent_workflow: nil
        ).and_return(run_service)
        expect(run_service).to receive(:execute).with(
          hash_including(session_ids: [creator_session.id])
        )

        handle_event
      end
    end

    context 'when the merge request has both direct and creator sessions' do
      let_it_be(:both_merge_request) do
        create(:merge_request, :unique_branches, source_project: project, target_project: project)
      end

      let_it_be(:direct_session) do
        create(:duo_workflows_workflow,
          project: project,
          user: both_merge_request.author,
          merge_request: both_merge_request,
          workflow_definition: ::Ai::Catalog::FoundationalFlow.developer_v1.reference)
      end

      let_it_be(:creator_session) do
        create(:duo_workflows_workflow,
          project: project,
          user: both_merge_request.author,
          workflow_definition: ::Ai::Catalog::FoundationalFlow.developer_v1.reference)
      end

      let_it_be(:creator_link) do
        create(:duo_workflows_workflow_merge_request,
          workflow: creator_session,
          merge_request: both_merge_request,
          project: project,
          link_type: :created)
      end

      let(:cloud_event) do
        MergeRequests::MergedCloudEvent.build(merge_request: both_merge_request, current_user: user)
      end

      it 'includes both session ids' do
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          project: project,
          current_user: both_merge_request.author,
          flow_trigger: flow_trigger,
          resource: both_merge_request,
          parent_workflow: nil
        ).and_return(run_service)
        expect(run_service).to receive(:execute).with(
          hash_including(session_ids: contain_exactly(direct_session.id, creator_session.id))
        )

        handle_event
      end
    end

    context 'when the merge request has no developer flow session' do
      let_it_be(:other_merge_request) do
        create(:merge_request, :unique_branches, source_project: project, target_project: project)
      end

      let(:cloud_event) do
        MergeRequests::MergedCloudEvent.build(merge_request: other_merge_request, current_user: user)
      end

      it 'does not start a flow' do
        expect(run_service).not_to receive(:execute)

        handle_event
      end

      context 'when the merge request has a session for another flow' do
        before_all do
          create(:duo_workflows_workflow,
            project: project,
            user: user,
            merge_request: other_merge_request,
            workflow_definition: 'software_development')
        end

        it 'does not start a flow' do
          expect(run_service).not_to receive(:execute)

          handle_event
        end
      end
    end

    context 'when a flow running for the merging user merges the merge request', :request_store do
      let_it_be(:flow_service_account) { create(:user, :service_account, composite_identity_enforced: true) }
      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

      let(:cloud_event) do
        ::Gitlab::ApplicationContext.with_context(duo_workflow_id: parent_workflow.id.to_s) do
          MergeRequests::MergedCloudEvent.build(merge_request: merge_request, current_user: user)
        end
      end

      before do
        stub_feature_flags(ai_flow_trigger_chaining: project.root_ancestor)
        ::Gitlab::Auth::Identity.fabricate(flow_service_account).link!(user, context: :authentication)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :update_duo_workflow, parent_workflow).and_return(true)
        allow(Ability).to receive(:allowed?)
          .with(merge_request.author, :update_duo_workflow, parent_workflow).and_return(false)
      end

      it 'authorizes the parent workflow against the merging user, not the author' do
        expect(Ai::FlowTriggers::RunService).to receive(:new)
          .with(hash_including(current_user: merge_request.author, parent_workflow: parent_workflow))
          .and_return(run_service)
        expect(run_service).to receive(:execute)

        handle_event
      end
    end
  end
end
