# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionFile, feature_category: :duo_agent_platform do
  subject(:session_file) { build(:duo_workflows_session_file) }

  describe 'associations' do
    it { is_expected.to belong_to(:workflow).class_name('Ai::DuoWorkflows::Workflow') }
    it { is_expected.to belong_to(:project).optional }
    it { is_expected.to belong_to(:namespace).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:size) }
    it { is_expected.to validate_numericality_of(:size).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:size).is_less_than_or_equal_to(described_class::MAX_SIZE) }
    it { is_expected.to validate_presence_of(:file) }
    it { is_expected.to validate_presence_of(:content_type) }
    it { is_expected.to validate_length_of(:content_type).is_at_most(255) }
    it { is_expected.to validate_inclusion_of(:content_type).in_array(described_class::ALLOWED_CONTENT_TYPES) }

    describe 'filename length' do
      # Stubbed: assigning a name this long fails when CarrierWave caches it to disk.
      before do
        allow(session_file.file).to receive(:filename).and_return(filename)
      end

      context 'when the filename is at the limit' do
        let(:filename) { 'a' * described_class::MAX_FILENAME_LENGTH }

        it { is_expected.to be_valid }
      end

      context 'when the filename is over the limit in bytes but not in characters' do
        let(:filename) { 'é' * ((described_class::MAX_FILENAME_LENGTH / 2) + 1) }

        it 'is invalid', :aggregate_failures do
          expect(session_file).not_to be_valid
          expect(session_file.errors[:file]).to include('name is too long (maximum is 255 bytes)')
        end
      end
    end
  end

  describe 'file storage' do
    it 'stores the file at the record id path' do
      session_file = create(:duo_workflows_session_file)

      expect(session_file.file.path).to end_with("ai/duo_workflows/session_file/file/#{session_file.id}/dk.png")
    end
  end

  describe 'sharding key' do
    let_it_be(:project) { create(:project) }
    let_it_be(:group) { create(:group) }

    it 'uses the workflow project for a project-level session' do
      workflow = create(:duo_workflows_workflow, project: project)

      expect(create(:duo_workflows_session_file, workflow: workflow))
        .to have_attributes(project_id: project.id, namespace_id: nil)
    end

    it 'uses the workflow namespace for a namespace-level session' do
      workflow = create(:duo_workflows_workflow, project: nil, namespace: group)

      expect(create(:duo_workflows_session_file, workflow: workflow))
        .to have_attributes(project_id: nil, namespace_id: group.id)
    end
  end

  describe 'when the workflow is deleted' do
    it 'keeps the row and nullifies workflow_id' do
      session_file = create(:duo_workflows_session_file)

      session_file.workflow.delete

      expect(session_file.reload.workflow_id).to be_nil
    end
  end

  describe 'when the project is deleted' do
    it 'keeps the row and nullifies workflow_id through the workflow cascade' do
      project = create(:project)
      session_file = create(:duo_workflows_session_file, workflow: create(:duo_workflows_workflow, project: project))

      project.delete

      expect(session_file.reload).to have_attributes(workflow_id: nil, project_id: project.id)
    end
  end

  describe 'when the namespace is deleted' do
    it 'keeps the row and nullifies workflow_id through the workflow cascade' do
      group = create(:group)
      session_file = create(:duo_workflows_session_file,
        workflow: create(:duo_workflows_workflow, project: nil, namespace: group))

      group.delete

      expect(session_file.reload).to have_attributes(workflow_id: nil, namespace_id: group.id)
    end
  end
end
