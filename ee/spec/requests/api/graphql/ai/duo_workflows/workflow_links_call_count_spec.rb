# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session link field call limits', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }
  let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  link_fields = %w[workItemLinks mergeRequestLinks noteLinks pipelineLinks workflowLinks inverseWorkflowLinks]

  before do
    stub_licensed_features(ai_workflows: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_next_found_instance_of(User) do |found_user|
      allow(found_user).to receive(:allowed_to_use?).and_return(true)
    end
  end

  def list_query(selection)
    graphql_query_for(:duo_workflow_workflows, { first: 10 }, "nodes { id #{selection} }")
  end

  def single_query(selection)
    graphql_query_for(:duo_workflow_workflows, { workflow_id: workflow.to_global_id.to_s },
      "nodes { id #{selection} }")
  end

  it 'resolves every link field for a single session' do
    selection = link_fields.map { |field| "#{field} { nodes { linkType } }" }.join(' ')

    post_graphql(single_query(selection), current_user: user)

    expect(graphql_errors).to be_nil
    expect(graphql_data_at(:duo_workflow_workflows, :nodes).size).to eq(1)
  end

  link_fields.each do |field|
    describe field do
      it 'rejects the field when selected for more than one session' do
        post_graphql(list_query("#{field} { nodes { linkType } }"), current_user: user)

        expect_graphql_errors_to_include(
          /"#{field}" field can be requested only for 1 DuoWorkflow\(s\) at a time/
        )
      end

      it 'rejects aliases that repeat the field on a single session' do
        selection = "first: #{field} { nodes { linkType } } second: #{field} { nodes { linkType } }"

        post_graphql(single_query(selection), current_user: user)

        expect_graphql_errors_to_include(/"#{field}" field can be requested only for 1 DuoWorkflow\(s\) at a time/)
      end
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(limit_duo_workflow_link_fields: false)
    end

    it 'resolves link fields for multiple sessions' do
      selection = link_fields.map { |field| "#{field} { nodes { linkType } }" }.join(' ')

      post_graphql(list_query(selection), current_user: user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:duo_workflow_workflows, :nodes).size).to eq(2)
    end
  end
end
