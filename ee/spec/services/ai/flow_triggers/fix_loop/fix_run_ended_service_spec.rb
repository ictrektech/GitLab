# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::FixRunEndedService, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :repository, :in_group) }
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

  let(:fix_run) do
    create(:duo_workflows_workflow, :finished,
      project: project,
      merge_request: merge_request,
      workflow_definition: Ai::FlowTriggers::FixLoop.developer_reference,
      trigger_event_type: :merge_request,
      trigger_flow_trigger: trigger)
  end

  let(:stop_service) { instance_double(Ai::FlowTriggers::FixLoop::StopService, execute: ServiceResponse.success) }

  subject(:result) { described_class.new(Ai::DuoWorkflows::Workflow.find(fix_run.id)).execute }

  before_all do
    create(:duo_workflows_workflow_merge_request, merge_request: merge_request, project: project, link_type: :created,
      workflow: create(:duo_workflows_workflow, project: project))
  end

  before do
    allow(Ai::FlowTriggers::FixLoop::Config).to receive(:for_project).with(project)
      .and_return(Ai::FlowTriggers::FixLoop::Config.new(nil))
    allow(Ai::FlowTriggers::FixLoop::StopService).to receive(:new).and_return(stop_service)
  end

  it 'marks the merge request as a draft and tells the author', :aggregate_failures do
    expect(result).to be_success
    expect(Ai::FlowTriggers::FixLoop::StopService).to have_received(:new).with(merge_request,
      service_account: trigger.service_account, reason: :fix_run_without_push, details: { fix_run: fix_run })
  end

  context 'when the check does not stop the loop' do
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
