# frozen_string_literal: true

FactoryBot.define do
  factory :duo_workflows_workflow, class: 'Ai::DuoWorkflows::Workflow' do
    project { association(:project) unless @overrides[:namespace] }
    user { association(:user, developer_of: project) }
    goal { "Fix pipeline" }
    agent_privileges { [Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES] }
    pre_approved_agent_privileges { [] }
    workflow_definition { "software_development" }
    image { "registry.gitlab.com/gitlab-org/duo-workflow/test-image:latest" }
    environment { :ide }

    trait :agentic_chat do
      workflow_definition { "chat" }
    end

    # A session started from the Duo CLI: the same workflow_definition as a web
    # Duo Developer session, told apart by the interactive flow version.
    trait :duo_cli do
      workflow_definition { "developer/v1" }
      environment { :ide }
      source_type { :duo_cli_interactive }
      flow_metadata_json do
        { flow_id: "developer", flow_version: "2.1.0-interactive", schema_version: "v1" }.to_json
      end
    end

    trait :created do
      status { 0 }
    end

    trait :running do
      status { 1 }
    end

    trait :finished do
      status { 3 }
    end

    trait :failed do
      status { 4 }
    end

    trait :stopped do
      status { 5 }
    end

    trait :input_required do
      status { 6 }
    end

    trait :plan_approval_required do
      status { 7 }
    end

    trait :external do
      environment { :external }
      agent_type { 'claude-code' }
    end

    trait :tool_call_approval_required do
      status { 8 }
    end

    trait :idle do
      status { 9 }
    end

    after(:build) do |workflow, _|
      workflow.project_id = nil if workflow.namespace_id
    end
  end
end
