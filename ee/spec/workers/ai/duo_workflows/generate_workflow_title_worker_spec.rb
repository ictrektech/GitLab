# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::GenerateWorkflowTitleWorker, feature_category: :duo_agent_platform do
  describe '#perform' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let(:title_service) { instance_double(Ai::DuoWorkflows::GenerateWorkflowTitleService) }

    subject(:perform) { described_class.new.perform(workflow.id) }

    it { expect(described_class).to be_idempotent }

    context 'when workflow is not found' do
      it 'does not call GenerateWorkflowTitleService' do
        expect(Ai::DuoWorkflows::GenerateWorkflowTitleService).not_to receive(:new)

        described_class.new.perform(non_existing_record_id)
      end
    end

    context 'when the service returns a title' do
      before do
        allow(Ai::DuoWorkflows::GenerateWorkflowTitleService).to receive(:new)
          .with(workflow: workflow)
          .and_return(title_service)
        allow(title_service).to receive(:execute).and_return('Fix the login bug')
      end

      it 'updates the workflow title' do
        perform

        expect(workflow.reload.title).to eq('Fix the login bug')
      end
    end

    context 'when the service returns a title longer than 40 characters' do
      let(:long_title) { 'a' * 100 }

      before do
        allow(Ai::DuoWorkflows::GenerateWorkflowTitleService).to receive(:new)
          .with(workflow: workflow)
          .and_return(title_service)
        allow(title_service).to receive(:execute).and_return(long_title)
      end

      it 'truncates the title to MAX_TITLE_LENGTH_IN_CHARS characters' do
        perform

        expect(workflow.reload.title.length).to be <= described_class::MAX_TITLE_LENGTH_IN_CHARS
      end
    end

    context 'when the service returns tool-call syntax instead of a title' do
      let_it_be(:workflow) do
        create(:duo_workflows_workflow, project: project, workflow_definition: 'risk_classification/v1')
      end

      where(:malformed_title) do
        [
          '<function_calls> <invoke name="gitlab_get_merge_request">',
          "<function_calls>\n<invoke name=\"fetch\">",
          '[{"type":"tool_use","id":"toolu_01Wr3abc","name":"fetch"}]',
          '{"type":"tool_use","id":"toolu_01Wr3abc"}',
          "  \n<invoke name=\"fetch\">"
        ]
      end

      with_them do
        before do
          allow(Ai::DuoWorkflows::GenerateWorkflowTitleService).to receive(:new)
            .with(workflow: workflow)
            .and_return(title_service)
          allow(title_service).to receive(:execute).and_return(malformed_title)
        end

        it 'keeps the default title' do
          expect { perform }.not_to change { workflow.reload.title }
        end
      end
    end

    context 'when the service returns a prose title for a flow with a default title' do
      let_it_be(:workflow) do
        create(:duo_workflows_workflow, project: project, workflow_definition: 'risk_classification/v1')
      end

      before do
        allow(Ai::DuoWorkflows::GenerateWorkflowTitleService).to receive(:new)
          .with(workflow: workflow)
          .and_return(title_service)
        allow(title_service).to receive(:execute).and_return('Review MR 257493 risk classification')
      end

      it 'replaces the default title' do
        perform

        expect(workflow.reload.title).to eq('Review MR 257493 risk classification')
      end
    end

    context 'when the service returns nil' do
      before do
        allow(Ai::DuoWorkflows::GenerateWorkflowTitleService).to receive(:new)
          .with(workflow: workflow)
          .and_return(title_service)
        allow(title_service).to receive(:execute).and_return(nil)
      end

      it 'does not update the workflow title' do
        expect { perform }.not_to change { workflow.reload.title }
      end
    end
  end
end
