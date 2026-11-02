# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SyncSessionArtifactWorker, feature_category: :duo_agent_platform do
  describe '.enqueue' do
    let_it_be(:workflow) { create(:duo_workflows_workflow) }

    subject(:enqueue) { described_class.enqueue(workflow) }

    context 'when ClickHouse is not enabled for analytics' do
      it 'enqueues the worker' do
        expect(described_class).to receive(:perform_async).with(workflow.id)

        enqueue
      end
    end

    context 'when ClickHouse is enabled for analytics' do
      before do
        allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
      end

      it 'enqueues the worker' do
        expect(described_class).to receive(:perform_async).with(workflow.id)

        enqueue
      end
    end
  end

  describe '#perform' do
    let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow) }

    subject(:perform) { described_class.new.perform(workflow_id) }

    context 'when workflow exists' do
      let(:workflow_id) { workflow.id }

      it 'syncs the session artifact' do
        expect(Ai::DuoWorkflows::SessionArtifact).to receive(:sync_from_workflow!).with(workflow)

        perform
      end

      it 'syncs the governance session' do
        expect(Ai::Governance::Session).to receive(:sync_from_workflow!).with(workflow)

        perform
      end

      it 'writes a row to both tables' do
        expect { perform }
          .to change { Ai::DuoWorkflows::SessionArtifact.count }.by(1)
          .and change { Ai::Governance::Session.count }.by(1)
      end

      it 'updates the same governance session on a later status change', :aggregate_failures do
        perform
        workflow.start!

        expect { described_class.new.perform(workflow_id) }.not_to change { Ai::Governance::Session.count }
        expect(Ai::Governance::Session.find_by(workflow_id: workflow.id).status).to eq('running')
      end

      context 'when ClickHouse is enabled for analytics' do
        before do
          allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
        end

        it 'writes the governance session but not the session artifact' do
          expect { perform }
            .to change { Ai::Governance::Session.count }.by(1)
            .and not_change { Ai::DuoWorkflows::SessionArtifact.count }
        end
      end

      context 'with a triggered workflow' do
        let_it_be(:workflow, freeze: false) { create(:duo_workflows_workflow, trigger_event_type: :mention) }

        it 'copies trigger_event_type onto the governance session' do
          perform

          expect(Ai::Governance::Session.find_by(workflow_id: workflow.id).trigger_event_type).to eq('mention')
        end
      end

      context 'with a group-scoped workflow' do
        let_it_be(:group) { create(:group) }
        let_it_be(:workflow, freeze: false) { create(:duo_workflows_workflow, project: nil, namespace: group) }

        it 'records the group namespace', :aggregate_failures do
          perform

          session = Ai::Governance::Session.find_by(workflow_id: workflow.id)
          expect(session.namespace_id).to eq(group.id)
          expect(session.project_id).to be_nil
        end
      end
    end

    context 'when workflow does not exist' do
      let(:workflow_id) { non_existing_record_id }

      it 'does not sync' do
        expect(Ai::DuoWorkflows::SessionArtifact).not_to receive(:sync_from_workflow!)
        expect(Ai::Governance::Session).not_to receive(:sync_from_workflow!)

        perform
      end
    end

    context 'when workflow is a note-mention session (gitlab_duo_note)' do
      let_it_be(:note_mention_workflow) do
        create(:duo_workflows_workflow, messaging_callback_context: { 'adapter' => 'gitlab_duo_note', 'note_id' => 1 })
      end

      let(:workflow_id) { note_mention_workflow.id }

      it 'syncs the session artifact' do
        expect(Ai::DuoWorkflows::SessionArtifact).to receive(:sync_from_workflow!).with(note_mention_workflow)

        perform
      end

      it 'syncs the governance session' do
        expect(Ai::Governance::Session).to receive(:sync_from_workflow!).with(note_mention_workflow)

        perform
      end

      it 'does not delete a previously synced artifact' do
        Ai::DuoWorkflows::SessionArtifact.sync_from_workflow!(note_mention_workflow)

        expect { perform }
          .not_to change { Ai::DuoWorkflows::SessionArtifact.for_workflow(note_mention_workflow.id).count }
      end
    end

    context 'when workflow is a private messaging session (slack)' do
      let_it_be(:messaging_workflow) do
        create(:duo_workflows_workflow, messaging_callback_context: { 'adapter' => 'slack' })
      end

      let(:workflow_id) { messaging_workflow.id }

      it 'does not sync' do
        expect(Ai::DuoWorkflows::SessionArtifact).not_to receive(:sync_from_workflow!)
        expect(Ai::Governance::Session).not_to receive(:sync_from_workflow!)

        perform
      end

      it 'writes to neither table' do
        expect { perform }
          .to not_change { Ai::DuoWorkflows::SessionArtifact.count }
          .and not_change { Ai::Governance::Session.count }
      end
    end
  end
end
