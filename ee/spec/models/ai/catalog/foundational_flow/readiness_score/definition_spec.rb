# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::ReadinessScore::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.readiness_score_v1 }

  it 'returns the readiness score foundational flow', :aggregate_failures do
    expect(flow).to have_attributes(
      foundational_flow_reference: 'readiness_score/v1',
      display_name: 'Readiness Score',
      feature_maturity: 'experimental',
      environment: 'web',
      goal_templates: ::Ai::Catalog::GoalTemplates::ReadinessScore,
      noteable_resolver: be_present
    )
  end

  it 'reads and writes GitLab only', :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB
    ])
  end

  it 'is gated by the workplan_score feature flag' do
    expect(flow.feature_flag).to eq('workplan_score')
  end

  it 'has no triggers and supports no trigger events', :aggregate_failures do
    expect(flow.triggers).to be_empty
    expect(flow.supported_events).to eq([])
  end

  describe '#resolve_noteable_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:work_item) { create(:work_item, project: project) }

    it 'returns the work item matching the URL embedded in the goal' do
      goal = "Score this: #{Gitlab::UrlBuilder.build(work_item)} thanks"

      expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
    end

    it 'resolves the legacy issues URL form' do
      goal = "See https://gitlab.com/#{project.full_path}/-/issues/#{work_item.iid}"

      expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(work_item)
    end

    it 'returns nil for a malformed goal' do
      expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
    end

    it 'returns nil for a nil goal' do
      expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
    end
  end
end
