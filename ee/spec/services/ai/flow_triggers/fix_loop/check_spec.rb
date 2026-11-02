# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::Check, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project) }
  let_it_be(:reviewer) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
  let_it_be(:human) { create(:user) }
  let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:creating_workflow) { create(:duo_workflows_workflow, project: project) }

  let(:content) { nil }

  let(:verdict_at) { Time.current }

  subject(:result) { described_class.new(merge_request, reviewer: reviewer, verdict_at: verdict_at).execute }

  before_all do
    create(:duo_workflows_workflow_merge_request,
      workflow: creating_workflow, merge_request: merge_request, project: project, link_type: :created)
  end

  before do
    allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project).with(project)
      .and_return(Ai::FlowTriggers::FixLoop::Config.new(content))
  end

  def create_fix_run(*traits, **attributes)
    create(:duo_workflows_workflow, *(traits.presence || [:finished]),
      project: project,
      merge_request: merge_request,
      workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
      trigger_event_type: :merge_request,
      **attributes)
  end

  shared_examples 'no fix run' do |reason|
    it "starts no fix run because of #{reason}", :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(reason)
    end
  end

  it 'starts a fix run', :aggregate_failures do
    expect(result).to be_success
    expect(result.payload[:fix_runs]).to eq(0)
  end

  context 'when the merge request is closed' do
    before do
      merge_request.close!
    end

    it_behaves_like 'no fix run', :not_open
  end

  context 'when the merge request is a draft' do
    before do
      merge_request.update!(title: "Draft: #{merge_request.title}")
    end

    it_behaves_like 'no fix run', :draft
  end

  context 'when no flow session created the merge request' do
    before do
      Ai::DuoWorkflows::WorkflowMergeRequest.where(merge_request: merge_request).update_all(link_type: :source)
    end

    it_behaves_like 'no fix run', :not_created_by_flow
  end

  context 'when the configuration is not valid' do
    let(:content) { "review:\n  max_rounds: 3\n" }

    it_behaves_like 'no fix run', :invalid_config

    it 'returns the configuration with its errors' do
      expect(result.payload[:config].errors).to contain_exactly('Unknown keys: `max_rounds`.')
    end
  end

  context 'when the configuration has a label' do
    let(:content) { "review:\n  label: software-factory\n" }

    it_behaves_like 'no fix run', :label_missing

    context 'when another key is not valid' do
      let(:content) { "review:\n  label: software-factory\n  max_fix_runs: 50\n" }

      it_behaves_like 'no fix run', :label_missing
    end

    context 'when the merge request has the label' do
      before do
        merge_request.update!(labels: [create(:label, project: project, title: 'software-factory')])
      end

      it 'starts a fix run' do
        expect(result).to be_success
      end
    end
  end

  context 'when another user requests changes' do
    subject(:result) { described_class.new(merge_request, reviewer: human, verdict_at: verdict_at).execute }

    it_behaves_like 'no fix run', :other_reviewer

    context 'when the configuration names that user' do
      let(:content) { "review:\n  reviewer: #{human.username}\n" }

      it 'starts a fix run' do
        expect(result).to be_success
      end
    end

    context 'when another key is not valid' do
      let(:content) { "review:\n  max_fix_runs: 50\n" }

      it_behaves_like 'no fix run', :other_reviewer
    end

    context 'when the reviewer of the configuration is not valid' do
      let(:content) { "review:\n  reviewer: 1\n" }

      it_behaves_like 'no fix run', :invalid_config
    end

    context 'when the file cannot be read' do
      let(:content) { "review: {\n" }

      it_behaves_like 'no fix run', :invalid_config
    end
  end

  describe 'a verdict that a fix run already answers' do
    subject(:result) { described_class.new(merge_request, reviewer: reviewer, verdict_at: 1.hour.ago).execute }

    context 'when a fix run started after the verdict' do
      before do
        create_fix_run
      end

      it_behaves_like 'no fix run', :verdict_answered

      it 'reads the fix runs from the primary' do
        lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(Ai::DuoWorkflows::Workflow.load_balancer)
        allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_return(lb_session)
        expect(lb_session).to receive(:use_primary).at_least(:once).and_call_original

        result
      end

      context 'when the configuration is not valid' do
        let(:content) { "review:\n  max_fix_runs: 50\n" }

        it_behaves_like 'no fix run', :invalid_config
      end
    end
  end

  describe 'an active fix run' do
    context 'when it started after the last push' do
      before do
        create_fix_run(:running)
      end

      it_behaves_like 'no fix run', :fix_run_not_pushed
    end

    # The review of a fix push comes while the fix run still replies in the threads.
    context 'when it started before the last push' do
      before do
        travel_to(2.hours.ago) { create_fix_run(:running) }
        create(:merge_request_diff, merge_request: merge_request)
      end

      it 'starts a fix run' do
        expect(result).to be_success
      end

      it 'reads the fix runs and the last push from the primary' do
        lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(Ai::DuoWorkflows::Workflow.load_balancer)
        allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_return(lb_session)
        expect(lb_session).to receive(:use_primary).twice.and_call_original

        result
      end
    end
  end

  context 'with fix runs in the loop' do
    before do
      create_list(:duo_workflows_workflow, 2, :finished,
        project: project,
        merge_request: merge_request,
        workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
        trigger_event_type: :merge_request)
    end

    it 'starts a fix run below max_fix_runs', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:fix_runs]).to eq(2)
    end

    context 'when the loop has max_fix_runs fix runs' do
      before do
        create_fix_run
      end

      it_behaves_like 'no fix run', :max_fix_runs

      # A second event for the verdict that stopped the loop must find the draft, not the limit again.
      context 'when the merge request is a draft' do
        before do
          merge_request.update!(title: "Draft: #{merge_request.title}")
        end

        it_behaves_like 'no fix run', :draft
      end

      it 'returns the count and the configuration', :aggregate_failures do
        expect(result.payload[:fix_runs]).to eq(3)
        expect(result.payload[:config].max_fix_runs).to eq(3)
      end
    end

    context 'when max_fix_runs is lower' do
      let(:content) { "review:\n  max_fix_runs: 2\n" }

      it_behaves_like 'no fix run', :max_fix_runs
    end
  end

  context 'with sessions that are not fix runs' do
    let(:content) { "review:\n  max_fix_runs: 1\n" }

    before do
      create_fix_run(trigger_event_type: :mention)
      create_fix_run(workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
      create(:duo_workflows_workflow,
        project: project,
        merge_request: create(:merge_request, source_project: project, source_branch: 'other-branch'),
        workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
        trigger_event_type: :merge_request)
    end

    it 'does not count them' do
      expect(result).to be_success
    end
  end

  describe 'the start of the loop' do
    let(:content) { "review:\n  max_fix_runs: 1\n" }

    before do
      travel_to(2.hours.ago) { create_fix_run }
    end

    it_behaves_like 'no fix run', :max_fix_runs

    context 'when a human marked the merge request as ready after the fix run' do
      before do
        travel_to(1.hour.ago) { SystemNoteService.handle_merge_request_draft(merge_request, project, human) }
      end

      it 'starts a new loop' do
        expect(result).to be_success
      end

      context 'when the loop has a fix run after that' do
        before do
          create_fix_run
        end

        it_behaves_like 'no fix run', :max_fix_runs
      end
    end

    context 'when a flow marked the merge request as ready after the fix run' do
      before do
        service_account = create(:service_account)

        travel_to(1.hour.ago) { SystemNoteService.handle_merge_request_draft(merge_request, project, service_account) }
      end

      it_behaves_like 'no fix run', :max_fix_runs
    end

    context 'when the reviewer approved after the fix run' do
      before do
        travel_to(1.hour.ago) { SystemNoteService.approve_mr(merge_request, reviewer) }
      end

      it 'starts a new loop' do
        expect(result).to be_success
      end
    end

    context 'when another user approved after the fix run' do
      before do
        travel_to(1.hour.ago) { SystemNoteService.approve_mr(merge_request, human) }
      end

      it_behaves_like 'no fix run', :max_fix_runs

      context 'when the configuration names that user as the reviewer' do
        let(:content) { "review:\n  max_fix_runs: 1\n  reviewer: #{human.username.upcase}\n" }

        subject(:result) { described_class.new(merge_request, reviewer: human, verdict_at: verdict_at).execute }

        it 'starts a new loop' do
          expect(result).to be_success
        end
      end
    end

    context 'when the merge request became a draft after the fix run' do
      before do
        travel_to(1.hour.ago) do
          merge_request.title = "Draft: #{merge_request.title}"
          SystemNoteService.handle_merge_request_draft(merge_request, project, human)
          merge_request.reload
        end
      end

      it_behaves_like 'no fix run', :max_fix_runs
    end
  end
end
