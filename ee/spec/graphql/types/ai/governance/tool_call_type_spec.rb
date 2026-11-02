# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::ToolCallType, feature_category: :compliance_management do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('AiGovernanceToolCall') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:tool_name, :title, :action_type, :count)
  end

  describe '#title' do
    it 'shows the Tool management display name of a governed tool' do
      expect(resolve_field(:title, { tool_name: 'gitlab_merge_request_search', governed: true }))
        .to eq('GitLab Merge Request Search')
    end

    it 'shows the recorded name when no rule governs the tool' do
      expect(resolve_field(:title, { tool_name: 'context7_query-docs', governed: false })).to eq('context7_query-docs')
    end
  end
end
