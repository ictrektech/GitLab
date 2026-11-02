# frozen_string_literal: true

FactoryBot.define do
  factory :duo_workflows_workflow_workflow, class: 'Ai::DuoWorkflows::WorkflowWorkflow' do
    workflow factory: :duo_workflows_workflow
    linked_workflow factory: :duo_workflows_workflow
    project { workflow.project }
    link_type { :source }
  end
end
