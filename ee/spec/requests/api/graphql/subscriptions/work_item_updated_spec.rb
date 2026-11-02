# frozen_string_literal: true

require "spec_helper"

RSpec.describe Subscriptions::WorkItemUpdated, feature_category: :team_planning do
  include GraphqlHelpers
  include Graphql::Subscriptions::WorkItems::Helper

  let_it_be(:reporter) { create(:user) }
  let_it_be(:project) { create(:project, reporters: reporter) }
  let_it_be_with_reload(:work_item) { create(:work_item, project: project) }
  let_it_be(:agent_plan) { create(:work_item_agent_plan, work_item: work_item, content: 'plan') }

  let(:subscribe) do
    mock_channel = Graphql::Subscriptions::ActionCable::MockActionCable.get_mock_channel
    query = <<~SUBSCRIPTION
      subscription {
        workItemUpdated(workItemId: "#{work_item.to_gid}") {
          id
          features { agentPlan { content contentHtml } }
        }
      }
    SUBSCRIPTION

    GitlabSchema.execute(query, context: { current_user: reporter, channel: mock_channel })

    mock_channel
  end

  let(:updated_work_item) { graphql_dig_at(graphql_data(response[:result]), :workItemUpdated) }

  before do
    stub_licensed_features(ai_workflows: true)
    stub_const('GitlabSchema', Graphql::Subscriptions::ActionCable::MockGitlabSchema)
    Graphql::Subscriptions::ActionCable::MockActionCable.clear_mocks
  end

  subject(:response) do
    subscription_response do
      GraphqlTriggers.work_item_updated(work_item)
    end
  end

  it 'pushes the agent plan without tracking an agent plan read' do
    expect { response }.not_to trigger_internal_events('work_item_agent_plan_read')

    expect(updated_work_item.dig('features', 'agentPlan', 'content')).to eq('plan')
  end
end
