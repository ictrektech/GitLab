# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.mlExperiment', feature_category: :mlops do
  include GraphqlHelpers

  let_it_be(:experiment) { create(:ml_experiments) }
  let_it_be(:project) { experiment.project }
  let_it_be(:current_user) { project.owner }
  let_it_be(:candidate) do
    create(:ml_candidates, :with_metrics_and_params, :with_metadata,
      project: project, experiment: experiment)
  end

  let(:user) { current_user }
  let(:boundary_object) { project }
  let(:experiment_selection) { 'id' }
  let(:query) { graphql_query_for(:ml_experiment, { id: global_id_of(experiment) }, experiment_selection) }
  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

  context 'when querying project.mlExperiments' do
    let(:experiment_fields) do
      <<~FIELDS
        mlExperiments {
          nodes {
            id
            name
            candidates {
              nodes {
                id
                _links { showPath artifactPath }
                params { nodes { id name } }
                metrics { nodes { id name } }
                metadata { nodes { id name } }
              }
            }
          }
        }
      FIELDS
    end

    let(:query) { graphql_query_for(:project, { full_path: project.full_path }, experiment_fields) }

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      [:read_project, :read_ml_experiment, :read_ml_flow_run]

    context 'with the getExperiments query of the experiment list page' do
      let(:query) do
        get_graphql_query_as_string('ml/experiment_tracking/graphql/queries/get_experiments.query.graphql')
      end

      def post_query
        post_graphql(query, current_user: current_user, variables: { fullPath: project.full_path })
      end

      def create_experiments(count)
        Array.new(count) do
          create(:ml_experiments, project: project, user: create(:user)).tap do |experiment|
            create_list(:ml_candidates, 2, project: project, experiment: experiment)
          end
        end
      end

      it 'does not run queries per experiment', :aggregate_failures do
        # A fresh value skips the lease-gated activity write, which could land on any request.
        User.find(current_user.id).update_column(:last_activity_on, Date.today) # rubocop:disable Rails/Date -- Users::ActivityService compares with Date.today
        create_experiments(1)
        post_query
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_query }

        create_experiments(2)

        expect { post_query }.not_to exceed_all_query_limit(control)
        expect(graphql_data_at(:project, :ml_experiments, :nodes).size).to eq(4)
      end
    end
  end

  context 'when the token is scoped to the experiment but not to its candidates' do
    let(:pat) do
      create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project),
        permissions: %w[read_ml_experiment])
    end

    let(:experiment_selection) { 'id candidates { nodes { id } }' }

    it 'returns the experiment without its candidates', :aggregate_failures do
      request

      expect(graphql_data_at(:ml_experiment, :id)).to be_present
      expect(graphql_data_at(:ml_experiment, :candidates, :nodes)).to all(be_nil)
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { _links { showPath artifactPath } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes _links] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { metrics { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes metrics nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { params { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes params nodes] }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
    [:read_ml_experiment, :read_ml_flow_run] do
    let(:experiment_selection) { 'candidates { nodes { metadata { nodes { id name } } } }' }
    let(:skipped_data_path) { %i[ml_experiment candidates nodes metadata nodes] }
  end
end
