# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::FixRunEndedCheck, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :repository, :in_group) }
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

  let(:status) { :finished }
  let(:fix_run) { create_fix_run(status) }
  let(:content) { nil }

  # A fresh session, as the worker loads it, so the merge request comes from the database.
  subject(:result) { described_class.new(Ai::DuoWorkflows::Workflow.find(fix_run.id)).execute }

  before_all do
    create(:duo_workflows_workflow_merge_request, merge_request: merge_request, project: project, link_type: :created,
      workflow: create(:duo_workflows_workflow, project: project))
  end

  before do
    allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project).with(project)
      .and_return(Ai::FlowTriggers::FixLoop::Config.new(content))
  end

  def create_fix_run(status, **attributes)
    create(:duo_workflows_workflow, status,
      project: project,
      merge_request: merge_request,
      workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
      trigger_event_type: :merge_request,
      trigger_flow_trigger: trigger,
      **attributes)
  end

  shared_examples 'stops the fix loop' do
    it 'stops the fix loop with the flow trigger of the fix run', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:trigger]).to eq(trigger)
    end
  end

  shared_examples 'does not stop the fix loop' do |reason|
    it "does not stop the fix loop because of #{reason}", :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(reason)
    end
  end

  it_behaves_like 'stops the fix loop'

  context 'when the fix run failed' do
    let(:status) { :failed }

    it_behaves_like 'stops the fix loop'

    context 'when the fix run did not start' do
      let(:fix_run) { create_fix_run(:failed, drop_reason: 'preconditions_not_met') }

      it_behaves_like 'does not stop the fix loop', :not_started
    end
  end

  context 'when a user stopped the fix run' do
    let(:status) { :stopped }

    it_behaves_like 'stops the fix loop'
  end

  context 'when the session is not a fix run' do
    context 'with another flow' do
      let(:fix_run) do
        create_fix_run(:finished,
          workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
      end

      it_behaves_like 'does not stop the fix loop', :not_fix_run
    end

    context 'with another event' do
      let(:fix_run) { create_fix_run(:finished, trigger_event_type: :mention) }

      it_behaves_like 'does not stop the fix loop', :not_fix_run
    end

    context 'without a flow trigger' do
      let(:fix_run) { create_fix_run(:finished, trigger_flow_trigger: nil) }

      it_behaves_like 'does not stop the fix loop', :not_fix_run
    end

    context 'with a flow trigger of another flow' do
      let(:other_trigger) do
        create(:ai_flow_trigger, project: project, event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
      end

      let(:fix_run) { create_fix_run(:finished, trigger_flow_trigger: other_trigger) }

      it_behaves_like 'does not stop the fix loop', :not_fix_run
    end

    context 'without a merge request' do
      let(:fix_run) { create_fix_run(:finished, merge_request: nil) }

      it_behaves_like 'does not stop the fix loop', :not_fix_run
    end
  end

  context 'when the merge request is already a draft' do
    before do
      merge_request.update!(title: "Draft: #{merge_request.title}")
    end

    it_behaves_like 'does not stop the fix loop', :draft
  end

  context 'when the configuration has a label that the merge request does not have' do
    let(:content) { "review:\n  label: software-factory\n" }

    it_behaves_like 'does not stop the fix loop', :label_missing

    context 'when another key is not valid' do
      let(:content) { "review:\n  label: software-factory\n  max_fix_runs: 50\n" }

      it_behaves_like 'does not stop the fix loop', :label_missing
    end
  end

  context 'when the configuration is not valid' do
    let(:content) { "review:\n  max_rounds: 3\n" }

    it_behaves_like 'does not stop the fix loop', :invalid_config
  end

  # The end of a fix run has no verdict, so no reviewer to check.
  context 'when the configuration names another reviewer' do
    let(:content) { "review:\n  reviewer: someone-else\n" }

    it_behaves_like 'stops the fix loop'
  end

  # The limit applies only to a new fix run.
  context 'when the loop has max_fix_runs fix runs' do
    before do
      travel_to(2.minutes.ago) { 2.times { create_fix_run(:finished) } }
    end

    it_behaves_like 'stops the fix loop'
  end

  context 'when a later fix run exists' do
    before do
      fix_run
      create_fix_run(:running)
    end

    it_behaves_like 'does not stop the fix loop', :not_last_fix_run
  end

  context 'when an earlier fix run is still running' do
    before do
      travel_to(1.minute.ago) { create_fix_run(:running) }
    end

    it_behaves_like 'does not stop the fix loop', :fix_run_active
  end

  context 'when an earlier fix run waits for input' do
    before do
      travel_to(1.minute.ago) { create_fix_run(:input_required) }
    end

    it_behaves_like 'does not stop the fix loop', :fix_run_active
  end

  context 'when an earlier fix run ended' do
    before do
      travel_to(1.minute.ago) { create_fix_run(:failed) }
    end

    it_behaves_like 'stops the fix loop'
  end

  describe 'the start of the loop' do
    before do
      fix_run
    end

    context 'when a human marked the merge request as ready after the fix run started' do
      before do
        travel_to(1.minute.from_now) { SystemNoteService.handle_merge_request_draft(merge_request, project, human) }
      end

      it_behaves_like 'does not stop the fix loop', :not_last_fix_run
    end

    context 'when the reviewer of the configuration approved after the fix run started' do
      before do
        travel_to(1.minute.from_now) { SystemNoteService.approve_mr(merge_request, reviewer) }
      end

      it_behaves_like 'does not stop the fix loop', :not_last_fix_run

      context 'when the configuration names another reviewer' do
        let(:content) { "review:\n  reviewer: #{human.username}\n" }

        it_behaves_like 'stops the fix loop'
      end
    end

    context 'when another user approved after the fix run started' do
      before do
        travel_to(1.minute.from_now) { SystemNoteService.approve_mr(merge_request, human) }
      end

      it_behaves_like 'stops the fix loop'

      context 'when the configuration names that user' do
        let(:content) { "review:\n  reviewer: #{human.username.upcase}\n" }

        it_behaves_like 'does not stop the fix loop', :not_last_fix_run
      end
    end
  end

  context 'when the merge request has a diff from after the start of the fix run' do
    let(:fix_run) { travel_to(1.day.ago) { create_fix_run(:finished) } }

    it_behaves_like 'does not stop the fix loop', :pushed
  end

  context 'when the merge request has no diff yet' do
    before do
      allow_next_found_instance_of(MergeRequest) do |found|
        allow(found).to receive(:merge_request_diff).and_return(MergeRequestDiff.new(merge_request_id: found.id))
      end
    end

    it_behaves_like 'stops the fix loop'
  end

  context 'when the source branch is ahead of the newest diff' do
    before do
      allow_next_found_instance_of(MergeRequest) do |found|
        allow(found).to receive(:source_branch_sha).and_return(Gitlab::Git::SHA1_BLANK_SHA)
      end
    end

    it_behaves_like 'does not stop the fix loop', :pushed
  end
end
