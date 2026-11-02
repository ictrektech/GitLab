# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::ConvertToGlCi::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.convert_to_gl_ci_v1 }

  it 'grants the privileges its flow config needs, including read-only files and run_command',
    :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
    ])
  end
end
