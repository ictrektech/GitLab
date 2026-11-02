# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowWorkflow, feature_category: :duo_agent_platform do
  subject(:workflow_workflow) { build(:duo_workflows_workflow_workflow) }

  it_behaves_like 'a duo workflow link model with project_xor_namespace validation' do
    let(:link_model) { workflow_workflow }
  end

  it { is_expected.to belong_to(:workflow) }
  it { is_expected.to belong_to(:linked_workflow) }
  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:namespace) }

  it { is_expected.to validate_presence_of(:workflow) }
  it { is_expected.to validate_presence_of(:linked_workflow) }
  it { is_expected.to validate_presence_of(:link_type) }

  it 'defines the link_type enum' do
    is_expected.to define_enum_for(:link_type)
      .with_values(source: 0)
      .with_prefix(:link_type)
  end

  describe 'uniqueness' do
    it 'is enforced per workflow, source workflow, and link type by the database', :aggregate_failures do
      existing = create(:duo_workflows_workflow_workflow)

      duplicate = build(:duo_workflows_workflow_workflow,
        workflow: existing.workflow, linked_workflow: existing.linked_workflow, link_type: existing.link_type)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'self-link' do
    subject(:self_link) { build(:duo_workflows_workflow_workflow, workflow: workflow, linked_workflow: workflow) }

    let_it_be(:workflow) { create(:duo_workflows_workflow) }

    it 'is invalid when the workflow is its own source', :aggregate_failures do
      expect(self_link).to be_invalid
      expect(self_link.errors[:linked_workflow]).to include('must be a different workflow')
    end

    it 'is rejected by the database' do
      expect { self_link.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /check_duo_wf_wf_wf_no_self_link/)
    end
  end

  describe '.ensure_link' do
    let_it_be(:project) { create(:project) }
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
    let_it_be(:source_workflow) { create(:duo_workflows_workflow, project: project) }

    let(:artifact) { source_workflow }
    let(:link_type) { :source }
    let(:artifact_attr) { :linked_workflow }

    it_behaves_like 'a duo workflow link model with ensure_link'
  end
end
