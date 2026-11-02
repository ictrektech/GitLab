# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::ReviewerApprovedCheck, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:reviewer) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
  let_it_be(:human) { create(:user) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:developer_item) do
    create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
  end

  let_it_be(:trigger) do
    create(:ai_flow_trigger, :for_catalog_consumer,
      project: project,
      ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
        project: project, item: developer_item),
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]]
    )
  end

  let(:approver) { reviewer }
  let(:approved_at) { Time.current }
  let(:content) { nil }

  subject(:result) { described_class.new(merge_request, reviewer: approver, approved_at: approved_at).execute }

  before_all do
    create(:duo_workflows_workflow_merge_request, merge_request: merge_request, project: project, link_type: :created,
      workflow: create(:duo_workflows_workflow, project: project))
  end

  before do
    create(:approval, merge_request: merge_request, user: reviewer)
    allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project).with(project)
      .and_return(Ai::FlowTriggers::FixLoop::Config.new(content))
  end

  def create_fix_run(at, **attributes)
    travel_to(at) do
      create(:duo_workflows_workflow, :finished,
        project: project,
        merge_request: merge_request,
        workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
        trigger_event_type: :merge_request,
        trigger_flow_trigger: trigger,
        **attributes)
    end
  end

  shared_examples 'adds no ready note' do |reason|
    it "adds no ready note because of #{reason}", :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(reason)
    end
  end

  context 'with fix runs in the loop' do
    before do
      create_fix_run(2.hours.ago)
      create_fix_run(1.hour.ago)
    end

    it 'adds the ready note with the flow trigger of the last fix run', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to eq(trigger: trigger, fix_runs: 2)
    end

    # CreateApprovalNoteWorker adds the system note of the approval after the event.
    context 'when the system note of this approval already exists' do
      before do
        travel_to(approved_at + 1.second) { SystemNoteService.approve_mr(merge_request, reviewer) }
      end

      it 'still counts the fix runs before the approval' do
        expect(result.payload[:fix_runs]).to eq(2)
      end
    end

    context 'when a human marked the merge request as ready after the approval' do
      before do
        travel_to(approved_at + 1.second) do
          SystemNoteService.handle_merge_request_draft(merge_request, project, human)
        end
      end

      it 'still counts the fix runs before the approval' do
        expect(result.payload[:fix_runs]).to eq(2)
      end
    end

    context 'when flows cannot start other flows' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
      end

      it 'still adds the ready note with the flow trigger of the last fix run' do
        expect(result.payload).to eq(trigger: trigger, fix_runs: 2)
      end
    end

    context 'when the reviewer approved an earlier loop' do
      before do
        travel_to(90.minutes.ago) { SystemNoteService.approve_mr(merge_request, reviewer) }
      end

      it 'counts only the fix runs of this loop' do
        expect(result.payload[:fix_runs]).to eq(1)
      end
    end

    context 'when the merge request is a draft' do
      before do
        merge_request.update!(title: "Draft: #{merge_request.title}")
      end

      it_behaves_like 'adds no ready note', :draft
    end

    context 'when the reviewer no longer approves the merge request' do
      before do
        merge_request.approvals.delete_all
      end

      it_behaves_like 'adds no ready note', :not_approved
    end

    context 'when the configuration is not valid' do
      let(:content) { "review:\n  max_rounds: 3\n" }

      it_behaves_like 'adds no ready note', :invalid_config
    end

    context 'when another user approves' do
      let(:approver) { human }

      it_behaves_like 'adds no ready note', :other_reviewer

      context 'when another key is not valid' do
        let(:content) { "review:\n  max_fix_runs: 50\n" }

        it_behaves_like 'adds no ready note', :other_reviewer
      end
    end

    context 'when the flow trigger of the last fix run no longer exists' do
      before do
        create_fix_run(30.minutes.ago, trigger_flow_trigger: nil)
      end

      it_behaves_like 'adds no ready note', :no_flow_trigger
    end
  end

  context 'without fix runs in the loop' do
    it 'adds the ready note with the flow trigger of the fix loop', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to eq(trigger: trigger, fix_runs: 0)
    end

    context 'with a fix run after the approval' do
      before do
        create_fix_run(approved_at + 1.minute)
      end

      it 'counts no fix run' do
        expect(result.payload).to eq(trigger: trigger, fix_runs: 0)
      end
    end

    context 'when another user approves' do
      let(:approver) { human }

      it_behaves_like 'adds no ready note', :other_reviewer
    end

    context 'when a human created the merge request' do
      before do
        Ai::DuoWorkflows::WorkflowMergeRequest.created_for_merge_request(merge_request).delete_all
      end

      it_behaves_like 'adds no ready note', :not_created_by_flow
    end

    context 'when the merge request does not have the label of the configuration' do
      let(:content) { "review:\n  label: duo-fix-loop\n" }

      it_behaves_like 'adds no ready note', :label_missing
    end

    context 'when flows cannot start other flows' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
      end

      it_behaves_like 'adds no ready note', :no_flow_trigger

      context 'when the reviewer of the configuration is a human' do
        let(:content) { "review:\n  reviewer: #{human.username}\n" }
        let(:approver) { human }

        before do
          create(:approval, merge_request: merge_request, user: human)
        end

        it 'adds the ready note with the flow trigger of the fix loop' do
          expect(result.payload).to eq(trigger: trigger, fix_runs: 0)
        end
      end
    end

    context 'when no flow trigger of the project starts a fix run' do
      before do
        Ai::FlowTrigger.id_in(trigger.id).update_all(active: false)
      end

      it_behaves_like 'adds no ready note', :no_flow_trigger
    end
  end
end
