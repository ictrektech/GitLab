# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::ReviewerApprovedService, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:reviewer) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
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

  let(:stop_service) { instance_double(Ai::FlowTriggers::FixLoop::StopService, execute: ServiceResponse.success) }

  subject(:result) { described_class.new(merge_request, reviewer: reviewer, approved_at: Time.current).execute }

  before_all do
    create(:duo_workflows_workflow_merge_request, merge_request: merge_request, project: project, link_type: :created,
      workflow: create(:duo_workflows_workflow, project: project))
    create(:approval, merge_request: merge_request, user: reviewer)
  end

  before do
    allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project).with(project)
      .and_return(Ai::FlowTriggers::FixLoop::Config.new(nil))
    allow(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).and_return(stop_service)
  end

  context 'with a fix run in the loop' do
    before do
      travel_to(1.hour.ago) do
        create(:duo_workflows_workflow, :finished,
          project: project,
          merge_request: merge_request,
          workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
          trigger_event_type: :merge_request,
          trigger_flow_trigger: trigger)
      end
    end

    it 'tells the author that the merge request is ready', :aggregate_failures do
      expect(result).to be_success
      expect(Ai::FlowTriggers::FixLoop::StopService).to have_received(:new).with(merge_request,
        service_account: trigger.service_account, reason: :approved, details: { reviewer: reviewer, fix_runs: 1 })
    end
  end

  context 'without a fix run in the loop' do
    it 'adds the service account to the project, and then tells the author', :aggregate_failures do
      expect(Ai::FlowTriggers::FixLoop).to receive(:add_inherited_service_account).with(trigger, project).ordered
      expect(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).with(merge_request,
        service_account: trigger.service_account, reason: :approved, details: { reviewer: reviewer, fix_runs: 0 })
        .ordered.and_return(stop_service)

      expect(result).to be_success
    end
  end

  context 'when the check adds no ready note' do
    before do
      merge_request.update!(title: "Draft: #{merge_request.title}")
    end

    it 'returns the reason of the check', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:draft)
      expect(Ai::FlowTriggers::FixLoop::StopService).not_to have_received(:new)
    end
  end
end
