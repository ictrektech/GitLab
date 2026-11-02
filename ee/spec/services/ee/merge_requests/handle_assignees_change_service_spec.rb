# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::HandleAssigneesChangeService, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, author: user, source_project: project) }

  let(:old_assignees) { [] }
  let(:options) { {} }

  let(:service) { described_class.new(project: project, current_user: user) }

  describe '#execute' do
    def execute
      service.execute(merge_request, old_assignees, options)
    end

    it 'schedules for analytics metric update' do
      expect(Analytics::CodeReviewMetricsWorker)
        .to receive(:perform_async).with('Analytics::RefreshReassignData', merge_request.id)

      execute
    end

    context 'when code_review_analytics is not available' do
      before do
        stub_licensed_features(code_review_analytics: false)
      end

      it 'does not schedule for analytics metric update' do
        expect(Analytics::CodeReviewMetricsWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when AI flow triggers are available' do
      let_it_be(:service_account) { create(:service_account, username: 'flow-trigger-1') }
      let_it_be(:flow_trigger) { create(:ai_flow_trigger, project: project, event_types: [1], user: service_account) }

      it 'runs the service' do
        allow(user).to receive(:can?).with(:trigger_ai_flow, project).and_return(true)

        merge_request.assignees = [service_account]

        run_service = instance_double(::Ai::FlowTriggers::RunService)

        expect(run_service).to receive(:execute).with(
          { input: merge_request.iid.to_s, event: :assign, triggered_by_username: user.username }
        )
        expect(::Ai::FlowTriggers::RunService).to receive(:new)
          .with(project: project, current_user: user, resource: merge_request, flow_trigger: flow_trigger,
            parent_workflow: nil)
          .and_return(run_service)

        execute
      end

      context 'when a flow made the assignment with a composite identity', :request_store do
        let_it_be(:flow_service_account) { create(:user, :service_account, composite_identity_enforced: true) }
        let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

        let(:duo_workflow_id) { parent_workflow.id.to_s }
        let(:run_service) { instance_double(::Ai::FlowTriggers::RunService, execute: nil) }

        def execute
          ::Gitlab::ApplicationContext.with_context(duo_workflow_id: duo_workflow_id) { super }
        end

        before do
          merge_request.assignees = [service_account]
          ::Gitlab::Auth::Identity.fabricate(flow_service_account).link!(user, context: :authentication)

          allow(user).to receive(:can?).and_call_original
          allow(user).to receive(:can?).with(:trigger_ai_flow, project).and_return(true)
          allow(user).to receive(:can?).with(:update_duo_workflow, parent_workflow).and_return(true)
        end

        it 'passes the parent workflow to RunService' do
          expect(::Ai::FlowTriggers::RunService).to receive(:new)
            .with(hash_including(current_user: user, parent_workflow: parent_workflow))
            .and_return(run_service)

          execute
        end

        shared_examples 'skips flow triggers without an authorized parent' do
          it 'does not run the flow and logs the reason' do
            expect(::Ai::FlowTriggers::RunService).not_to receive(:new)
            expect(::Gitlab::AppLogger).to receive(:info).with(hash_including(
              message: 'Flow-originated assignment without an authorized parent workflow, skipping flow triggers',
              reason: :non_human_trigger_not_permitted,
              Labkit::Fields::GL_PROJECT_ID => project.id
            ))

            execute
          end
        end

        context 'without a workflow id' do
          let(:duo_workflow_id) { nil }

          it_behaves_like 'skips flow triggers without an authorized parent'
        end

        context 'when the user may not update the workflow' do
          let(:duo_workflow_id) { create(:duo_workflows_workflow, project: project).id.to_s }

          it_behaves_like 'skips flow triggers without an authorized parent'
        end

        context 'when ai_flow_trigger_chaining is disabled' do
          before do
            stub_feature_flags(ai_flow_trigger_chaining: false)
          end

          it 'runs the flow without a parent workflow' do
            expect(::Ai::FlowTriggers::RunService).to receive(:new)
              .with(hash_including(parent_workflow: nil))
              .and_return(run_service)

            execute
          end
        end
      end

      context 'when a human made the assignment' do
        it 'does not look up a parent workflow' do
          allow(user).to receive(:can?).with(:trigger_ai_flow, project).and_return(true)
          merge_request.assignees = [service_account]

          expect(::Ai::FlowTriggers::CallerContext).not_to receive(:authorized_parent_workflow)
          expect(::Ai::FlowTriggers::RunService).to receive(:new)
            .with(hash_including(parent_workflow: nil))
            .and_return(instance_double(::Ai::FlowTriggers::RunService, execute: nil))

          ::Gitlab::ApplicationContext.with_context(duo_workflow_id: '1') { execute }
        end
      end
    end
  end
end
