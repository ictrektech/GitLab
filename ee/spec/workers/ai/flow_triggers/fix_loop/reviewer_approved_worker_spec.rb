# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::ReviewerApprovedWorker, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:reviewer) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:approval) { create(:approval, merge_request: merge_request, user: reviewer) }

  let(:event) do
    MergeRequests::ApprovedCloudEvent.build(merge_request: merge_request, current_user: reviewer, approval: approval)
  end

  let(:service_response) { ServiceResponse.success }
  let(:service) { instance_double(Ai::FlowTriggers::FixLoop::ReviewerApprovedService, execute: service_response) }
  let(:worker) { described_class.new }

  before_all do
    create(:ai_flow_trigger, project: project, event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
  end

  before do
    allow(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).to receive(:new).and_return(service)
  end

  def handle_event
    worker.handle_event(event)
  end

  it_behaves_like 'subscribes to event'

  context 'when no flow trigger of the project starts on merge request events' do
    let_it_be(:other_project) { create(:project, :in_group) }
    let_it_be(:other_merge_request) do
      create(:merge_request, source_project: other_project, target_project: other_project)
    end

    let(:event) do
      MergeRequests::ApprovedCloudEvent.build(merge_request: other_merge_request, current_user: reviewer,
        approval: create(:approval, merge_request: other_merge_request, user: reviewer))
    end

    it_behaves_like 'ignores the published event'
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(dap_software_factory: false)
    end

    it_behaves_like 'ignores the published event'
  end

  context 'when dap_software_factory is enabled for the project only' do
    before do
      stub_feature_flags(dap_software_factory: project)
    end

    it_behaves_like 'subscribes to event'
  end

  it 'does not inherit the composite identity of the enqueuing context' do
    expect(described_class.skip_composite_identity_passthrough?).to be(true)
  end

  it 'defers only on database-wide health signals' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [], indicators: Gitlab::Database::HealthStatus::GLOBAL_INDICATORS)
  end

  describe '.dispatch?' do
    it 'is false for a project that no longer exists' do
      allow(Project).to receive(:find_by_id).with(project.id).and_return(nil)

      expect(described_class.dispatch?(event)).to be(false)
    end
  end

  describe '#handle_event' do
    it 'checks the approval at the time of the approval' do
      handle_event

      expect(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).to have_received(:new)
        .with(merge_request, reviewer: reviewer, approved_at: be_within(0.001).of(approval.created_at))
    end

    context 'when the check adds no ready note' do
      let(:service_response) { ServiceResponse.error(message: 'Merge request is a draft.', reason: :draft) }

      it 'logs the reason' do
        expect(worker.logger).to receive(:info).with(hash_including(
          'message' => 'Fix loop ready note not added: Merge request is a draft.',
          'reason' => :draft,
          'merge_request_id' => merge_request.id
        ))

        handle_event
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(dap_software_factory: false)
      end

      it 'does not check the approval' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).not_to have_received(:new)
      end
    end

    context 'when dap_software_factory is enabled for the project only' do
      before do
        stub_feature_flags(dap_software_factory: project)
      end

      it 'checks the approval' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).to have_received(:new)
      end
    end

    context 'when the merge request no longer exists' do
      before do
        allow(MergeRequest).to receive(:find_by_id).with(merge_request.id).and_return(nil)
      end

      it 'does not check the approval' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).not_to have_received(:new)
      end
    end

    context 'when the approver no longer exists' do
      before do
        allow(event).to receive(:current_user).and_return(nil)
      end

      it 'does not check the approval' do
        handle_event

        expect(Ai::FlowTriggers::FixLoop::ReviewerApprovedService).not_to have_received(:new)
      end
    end
  end
end
