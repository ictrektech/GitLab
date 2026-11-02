# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::RecommendReviewers::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.recommend_reviewers_v1 }

  it 'runs on merge request events' do
    expect(flow.triggers).to contain_exactly(::Ai::FlowTrigger::EVENT_TYPES[:merge_request])
  end

  it_behaves_like 'a foundational flow precondition',
    hook_scope: :merge_request, field: 'action', allowed: %w[created], denied: %w[approved merged]

  it 'provisions triggers that run on created merge requests only' do
    expect(flow.default_trigger_filter).to eq(
      'merge_request' => { 'rules' => [{ 'field' => 'action', 'operator' => 'in', 'value' => ['created'] }] }
    )
  end

  it 'resolves additional context with the Context class' do
    expect(flow.additional_context_resolver).to eq(Ai::Catalog::FoundationalFlow::RecommendReviewers::Context)
  end

  it 'accepts merge requests only' do
    expect(flow.supported_resource_types).to eq([::MergeRequest])
  end

  describe 'additional_context_resolver' do
    let_it_be(:project) { create(:project) }

    it 'resolves reviewer data for a merge request' do
      merge_request = create(:merge_request, source_project: project, target_project: project)

      expect(flow.resolve_additional_context_for(resource: merge_request))
        .to include('current_reviewers', 'approval_rules')
    end

    it 'resolves to no context for a resource that is not a merge request' do
      expect(::Ai::Catalog::FoundationalFlow::RecommendReviewers::Context).not_to receive(:new)
      expect(flow.resolve_additional_context_for(resource: create(:issue, project: project))).to be_nil
    end
  end

  describe 'resolve_flow_version_for' do
    let_it_be(:project) { create(:project) }

    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

    it 'requests version 3.0.0 or later' do
      expect(resolved).to eq(
        flow_config_id: 'recommend_reviewers',
        flow_config_schema_version: 'v1',
        flow_version: '^3.0.0'
      )
    end
  end
end
