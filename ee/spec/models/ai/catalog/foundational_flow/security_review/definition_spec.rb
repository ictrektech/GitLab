# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SecurityReview::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.security_review_v1 }

  it 'returns the security review foundational flow', :aggregate_failures do
    expect(flow.foundational_flow_reference).to eq('security_review/v1')
    expect(flow.flow_version).to eq('^2.0.0')
    expect(flow.display_name).to eq('Security Review')
    expect(flow.description).to eq('Review merge request code changes for business logic security vulnerabilities.')
    expect(flow.feature_maturity).to eq('beta')
    expect(flow.ai_feature).to eq('security_review')
    expect(flow.environment).to eq('web')
    expect(flow.ultimate_only).to be true
    expect(flow.suppress_mention_progress_note).to be true
  end

  it 'grants only the file and GitLab privileges its flow config needs', :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
    ])
  end

  it 'is beta' do
    expect(Ai::Catalog::FoundationalFlow.beta?('security_review/v1')).to be true
  end

  it 'is ultimate-only' do
    expect(Ai::Catalog::FoundationalFlow.ultimate_only?('security_review/v1')).to be true
  end
end
