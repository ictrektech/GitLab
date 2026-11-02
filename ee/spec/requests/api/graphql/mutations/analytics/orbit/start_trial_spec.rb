# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'OrbitStartTrial mutation', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true) }
  let(:current_user) { owner }
  let(:input) { { group_path: group.full_path } }
  let(:mutation) { graphql_mutation(:orbit_start_trial, input, 'group { id orbit { enabled } } errors') }

  def mutation_response
    graphql_mutation_response(:orbit_start_trial)
  end

  before_all do
    group.add_owner(owner)
    group.add_maintainer(maintainer)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_trial: group)

    allow(client).to receive(:start_product_trial)
      .with(trial_type: :orbit, namespace_id: group.id)
      .and_return(::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: true))
    allow(client).to receive(:expire_product_trial_cache)
    allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(trial)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :start_orbit_trial do
    let(:user) { owner }
    let(:boundary_object) { group }
    let(:mutation) { graphql_mutation(:orbit_start_trial, input, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'as an owner' do
    it 'starts the trial, records it, and turns on Orbit', :aggregate_failures do
      expect do
        post_graphql_mutation(mutation, current_user: current_user)
      end.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)

      expect(mutation_response).to include(
        'group' => hash_including('id' => group.to_global_id.to_s, 'orbit' => { 'enabled' => true }),
        'errors' => be_empty
      )
      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end

    context 'when CDot reports an existing trial that has ended' do
      let(:trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false) }

      before do
        allow(client).to receive(:start_product_trial).and_return(
          ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
            success: false, error_code: :trial_already_active
          )
        )
      end

      it 'returns the trial-ended error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to contain_exactly(
          'The GitLab Orbit trial has ended. Contact sales to keep using GitLab Orbit.'
        )
      end
    end

    context 'when CDot rejects the group as ineligible' do
      before do
        allow(client).to receive(:start_product_trial).and_return(
          ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
            success: false, error_code: :ineligible, error_message: 'Namespace already used its trial'
          )
        )
      end

      it 'returns the ineligible message, not the CDot reason' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to contain_exactly('Contact sales to get GitLab Orbit for this group.')
      end
    end

    context 'when CDot is unreachable' do
      before do
        allow(client).to receive(:start_product_trial)
          .and_raise(::Gitlab::SubscriptionPortal::StartProductTrialResponse::Error, 'boom')
      end

      it 'returns a generic unavailable error' do
        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors'])
          .to contain_exactly('GitLab Orbit is not available right now. Try again later.')
      end
    end

    context 'when the group is excluded from indexing' do
      before do
        create(:knowledge_graph_excluded_namespace, namespace: group)
      end

      it 'returns the cannot-be-indexed error and never calls CDot' do
        expect(client).not_to receive(:start_product_trial)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to contain_exactly(
          'This top-level group is excluded. Remove the exclusion to turn on GitLab Orbit.'
        )
      end
    end
  end

  context 'as a maintainer' do
    let(:current_user) { maintainer }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the group is in the Orbit beta' do
    before do
      create(:orbit_namespace_enrollment, :beta, namespace: group)
      stub_feature_flags(orbit_promo_access_gate: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the group is a subgroup' do
    let_it_be(:subgroup) { create(:group, parent: group) }
    let(:input) { { group_path: subgroup.full_path } }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the group does not exist' do
    let(:input) { { group_path: 'nonexistent/path' } }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the orbit_trial flag is disabled for the group' do
    before do
      stub_feature_flags(orbit_trial: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'never calls CDot' do
      expect(client).not_to receive(:start_product_trial)

      post_graphql_mutation(mutation, current_user: current_user)
    end
  end

  context 'when the orbit license is not available' do
    before do
      stub_licensed_features(orbit: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end
end
