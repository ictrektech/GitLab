# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::WorkflowTriggerable, feature_category: :vulnerability_management do
  let(:worker_class) do
    Class.new do
      def self.name
        'TestWorkflowWorker'
      end

      include ApplicationWorker
      include Vulnerabilities::WorkflowTriggerable
    end
  end

  let(:worker) { worker_class.new }

  describe '#resolve_workflow_user' do
    let_it_be(:project) { create(:project) }
    let_it_be(:author) { create(:user) }
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project, author: author) }

    context 'when author has duo_workflow permission' do
      before do
        allow(Ability).to receive(:allowed?).with(author, :duo_workflow, project).and_return(true)
      end

      it 'returns the author' do
        result = worker.send(:resolve_workflow_user, vulnerability, project)

        expect(result).to eq(author)
      end

      it 'does not log any info message' do
        expect(Gitlab::AppLogger).not_to receive(:info)

        worker.send(:resolve_workflow_user, vulnerability, project)
      end
    end

    context 'when author does not have duo_workflow permission' do
      before do
        allow(Ability).to receive(:allowed?).with(author, :duo_workflow, project).and_return(false)
      end

      it 'returns nil' do
        result = worker.send(:resolve_workflow_user, vulnerability, project)

        expect(result).to be_nil
      end

      it 'logs an info message' do
        expect(Gitlab::AppLogger).to receive(:info).with(
          message: 'Vulnerability author does not have duo_workflow permission',
          vulnerability_id: vulnerability.id,
          project_id: project.id,
          author_id: author.id
        )

        worker.send(:resolve_workflow_user, vulnerability, project)
      end
    end

    context 'when author is nil' do
      before do
        allow(vulnerability).to receive(:author).and_return(nil)
      end

      it 'returns nil' do
        result = worker.send(:resolve_workflow_user, vulnerability, project)

        expect(result).to be_nil
      end

      it 'logs an info message with nil author_id' do
        expect(Gitlab::AppLogger).to receive(:info).with(
          message: 'Vulnerability author does not have duo_workflow permission',
          vulnerability_id: vulnerability.id,
          project_id: project.id,
          author_id: nil
        )

        worker.send(:resolve_workflow_user, vulnerability, project)
      end
    end

    context 'when a bulk initiator is recorded' do
      let_it_be(:initiator) { create(:user) }

      let(:initiator_id) { initiator.id }
      let(:can_execute_vulnerability_duo_workflow) { true }
      let(:can_duo_workflow) { true }

      before do
        allow(worker).to receive(:bulk_initiator_id).and_return(initiator_id)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(author, :duo_workflow, project).and_return(true)
        allow(Ability).to receive(:allowed?)
          .with(initiator, :execute_vulnerability_duo_workflow, project)
          .and_return(can_execute_vulnerability_duo_workflow)
        allow(Ability).to receive(:allowed?).with(initiator, :duo_workflow, project).and_return(can_duo_workflow)
      end

      context 'when the initiator can still run the workflow' do
        it 'returns the initiator instead of the author' do
          expect(worker.send(:resolve_workflow_user, vulnerability, project)).to eq(initiator)
        end
      end

      shared_examples 'skips the initiator for a missing permission' do |permission|
        it 'returns nil without falling back to the author' do
          expect(worker.send(:resolve_workflow_user, vulnerability, project)).to be_nil
        end

        it 'logs the missing permission' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            message: 'Bulk workflow initiator does not have permission to run the workflow',
            missing_permission: permission,
            vulnerability_id: vulnerability.id,
            project_id: project.id,
            initiator_id: initiator.id
          )

          worker.send(:resolve_workflow_user, vulnerability, project)
        end
      end

      context 'when the initiator can no longer start bulk runs, for example after a demotion to Developer' do
        let(:can_execute_vulnerability_duo_workflow) { false }

        it_behaves_like 'skips the initiator for a missing permission', :execute_vulnerability_duo_workflow
      end

      context 'when the initiator no longer has Duo workflow access' do
        let(:can_duo_workflow) { false }

        it_behaves_like 'skips the initiator for a missing permission', :duo_workflow
      end

      context 'when the initiator no longer exists' do
        let(:initiator_id) { non_existing_record_id }

        it 'returns nil without falling back to the author' do
          expect(worker.send(:resolve_workflow_user, vulnerability, project)).to be_nil
        end

        it 'logs that the initiator was not found' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            message: 'Bulk workflow initiator not found',
            vulnerability_id: vulnerability.id,
            project_id: project.id,
            initiator_id: non_existing_record_id
          )

          worker.send(:resolve_workflow_user, vulnerability, project)
        end
      end
    end
  end

  describe '#log_no_eligible_user' do
    let_it_be(:project) { create(:project) }
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }

    it 'logs an error with vulnerability and project context' do
      expect(Gitlab::AppLogger).to receive(:error).with(
        message: 'No eligible user found for vulnerability workflow, ' \
          'author lacks duo_workflow permission',
        vulnerability_id: vulnerability.id,
        project_id: project.id
      )

      worker.send(:log_no_eligible_user, vulnerability, project)
    end

    context 'when a bulk initiator is recorded' do
      before do
        allow(worker).to receive(:bulk_initiator_id).and_return(42)
      end

      it 'logs an error that names the bulk initiator' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          message: 'No eligible user found for vulnerability workflow, ' \
            'bulk initiator is not eligible',
          initiator_id: 42,
          vulnerability_id: vulnerability.id,
          project_id: project.id
        )

        worker.send(:log_no_eligible_user, vulnerability, project)
      end
    end
  end
end
