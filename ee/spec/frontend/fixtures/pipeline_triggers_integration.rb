# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline triggers Integration (JavaScript fixtures)', type: :request, feature_category: :continuous_integration do
  include ApiHelpers
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:namespace) { create(:group, name: 'frontend-fixtures', path: 'frontend-fixtures') }
  let_it_be(:project, freeze: false) { create(:project, namespace: namespace, path: 'pipeline-triggers-project') }
  let_it_be(:user) { create(:user) }
  let_it_be(:other_maintainer) { create(:user) }
  let_it_be(:guest) { create(:user) }

  # One trigger per state the list renders differently: the signed-in user's own token is
  # exposed in full, another maintainer's token is shortened, and a guest's trigger is
  # flagged as unable to access the project.
  let_it_be(:owned_trigger) { create(:ci_trigger, project: project, owner: user, description: 'Owned trigger') }
  let_it_be(:other_trigger) do
    create(:ci_trigger, project: project, owner: other_maintainer, description: "Another user's trigger")
  end

  let_it_be(:invalid_trigger) do
    create(:ci_trigger, project: project, owner: guest, description: 'Trigger owned by a guest')
  end

  base_output_path = 'graphql/ci/pipeline_triggers/integration/'

  before_all do
    project.add_maintainer(user)
    project.add_maintainer(other_maintainer)
    project.add_guest(guest)
  end

  describe 'embedded page data' do
    # The list reads its rows from the `data-triggers` attribute the CI/CD settings page
    # renders, not from a request, so this records what the controller serializes into it.
    # The fixture helper stores `response` after the example.
    let(:triggers) do
      ::Ci::TriggerSerializer.new.represent(
        project.triggers.with_last_used, current_user: user, project: project
      )
    end

    # The fixture helper stores `response` after the example.
    def response
      Gitlab::Json.dump(triggers)
    end

    it "#{base_output_path}triggers.json" do
      expect(triggers.pluck(:has_token_exposed)).to contain_exactly(true, false, false)
      expect(triggers.pluck(:can_access_project)).to contain_exactly(true, true, false)
    end
  end

  describe GraphQL::Query, 'mutations' do
    let(:new_description) { 'Renamed trigger' }
    let(:mutation) do
      get_graphql_query_as_string('ci_settings_pipeline_triggers/graphql/update_pipeline_trigger.mutation.graphql')
    end

    it "#{base_output_path}update_pipeline_trigger.mutation.graphql.json" do
      post_graphql(mutation, current_user: user, variables: {
        id: owned_trigger.to_global_id.to_s,
        description: new_description
      })

      expect_graphql_errors_to_be_empty

      response_data = graphql_mutation_response(:pipeline_trigger_update)

      expect(response_data['errors']).to eq([])
      expect(response_data.dig('pipelineTrigger', 'description')).to eq(new_description)
    end
  end
end
