# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SlackAssistant::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.slack_assistant_v1 }

  it 'pre-approves reads only, so writes and flow starts need approval', :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
    ])
    expect(flow.pre_approved_agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB
    ])
  end

  # The Duo Workflow Service drops an admin's `ask` rules for a flow that
  # cannot reach its user, so this has to be true for those rules to apply.
  it 'can pause to ask its user' do
    expect(flow.allow_agent_to_request_user).to be true
  end
end
