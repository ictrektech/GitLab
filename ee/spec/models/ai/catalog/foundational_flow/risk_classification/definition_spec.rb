# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RiskClassification::Definition, feature_category: :dap_code_review do
  subject(:flow) { Ai::Catalog::FoundationalFlow.risk_classification_v1 }

  describe '#triggers' do
    it 'runs on merge request events only' do
      expect(flow.triggers).to contain_exactly(::Ai::FlowTrigger::EVENT_TYPES[:merge_request])
    end
  end

  describe '#precondition' do
    it_behaves_like 'a foundational flow precondition',
      hook_scope: :merge_request, field: 'action', allowed: %w[created], denied: %w[approved merged]
  end

  describe '#default_trigger_filter' do
    it 'provisions triggers that run on created merge requests only' do
      expect(flow.default_trigger_filter).to eq(
        'merge_request' => { 'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => ['created'] }] }
      )
    end
  end

  describe '#supported_resource_types' do
    it 'accepts merge requests only' do
      expect(flow.supported_resource_types).to eq([::MergeRequest])
    end
  end

  it 'grants only the file and GitLab privileges its flow config needs', :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
    ])
  end

  describe '#suppress_progress_note' do
    it 'is enabled, so the flow does not add a generic progress note' do
      expect(flow.suppress_progress_note).to be true
    end
  end

  describe '#run_on_session_created' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project) }

    it 'queues an assessment, so the widget can tell running from never run' do
      flow.run_on_session_created(resource: merge_request)

      assessment = merge_request.reload.risk_assessment
      expect(assessment).to be_queued
      expect(assessment.diff_sha).to eq(merge_request.diff_head_sha)
    end

    it 'schedules the timeout that expires an assessment the flow abandons' do
      expect(::Ai::RiskAssessment::TimeoutWorker).to receive(:perform_in).with(
        ::Ai::RiskAssessment::TimeoutWorker::TIMEOUT_DURATION, merge_request.id
      )

      flow.run_on_session_created(resource: merge_request)
    end

    context 'when an assessment already exists' do
      let(:previous_sha) { Digest::SHA1.hexdigest('older') } # rubocop:disable Fips/SHA1 -- test data

      before do
        create(:merge_requests_risk_assessment, :complete, merge_request: merge_request, diff_sha: previous_sha)
      end

      it 'reuses the row, so the previous score stays readable until a new one lands' do
        expect { flow.run_on_session_created(resource: merge_request) }
          .not_to change { MergeRequests::RiskAssessment.count }

        assessment = merge_request.reload.risk_assessment
        expect(assessment.diff_sha).to eq(previous_sha)
        expect(assessment).to be_queued
      end

      it 'still schedules a timeout, so this run gets its own backstop' do
        expect(::Ai::RiskAssessment::TimeoutWorker).to receive(:perform_in)

        flow.run_on_session_created(resource: merge_request)
      end
    end

    context 'when a run is already in flight' do
      let!(:assessment) { create(:merge_requests_risk_assessment, :queued, merge_request: merge_request) }

      it 'schedules no second timeout, so the timer already watching the row stands' do
        expect(::Ai::RiskAssessment::TimeoutWorker).not_to receive(:perform_in)

        flow.run_on_session_created(resource: merge_request)
      end

      it 'touches the row, so the timeout counts from this attempt rather than the first' do
        expect { flow.run_on_session_created(resource: merge_request) }
          .to change { assessment.reload.updated_at }
      end
    end

    it 'ignores a resource that is not a merge request' do
      expect { flow.run_on_session_created(resource: create(:issue, project: project)) }
        .not_to change { MergeRequests::RiskAssessment.count }
    end
  end
end
