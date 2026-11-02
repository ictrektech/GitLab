# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Refresh the Secrets Manager entitlement', :saas, :use_clean_rails_memory_store_caching,
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:current_user) { owner }
  let(:target_group) { root_group }
  let(:mutation_name) { :secrets_manager_refresh_entitlement }

  let(:consent_given) do
    ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible, on_demand_enabled: true)
  end

  let(:resolve_response) { ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false) }

  let(:mutation) { graphql_mutation(mutation_name, group_path: target_group.full_path) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before_all do
    root_group.add_owner(owner)
    root_group.add_maintainer(maintainer)
    subgroup.add_owner(owner)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(native_secrets_management: true)
    allow(client).to receive_messages(secrets_manager_trial: consent_given,
      secrets_manager_consumer_resolve: resolve_response)
  end

  context 'when the current user is the group owner' do
    it 'returns the entitlement as CDot reports it now', :aggregate_failures do
      post_mutation

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['entitlement']).to include('state' => 'TRIAL_ELIGIBLE', 'onDemandEnabled' => true)
    end

    it 'asks CDot about the group past its caches, with the entitlement timeout' do
      post_mutation

      expect(client).to have_received(:secrets_manager_trial)
        .with(namespace_id: root_group.id, timeout: ::SecretsManagement::Entitlement::DEFAULT_HTTP_TIMEOUT_SECONDS,
          fresh: true)
    end

    it 'does not record add-on intent or provision the secrets manager', :aggregate_failures do
      post_mutation

      expect(::SecretsManagement::NamespaceEnrollment.find_by_namespace_id(root_group.id)).to be_nil
      expect(root_group.reload.secrets_manager).to be_nil
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[enable_secrets_manager_add_on read_secrets_manager] do
      let(:user) { owner }
      let(:boundary_object) { root_group }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    context 'when CDot is unreachable' do
      before do
        allow(client).to receive(:secrets_manager_trial)
          .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError, 'boom')
      end

      it 'returns a generic unavailable error without an entitlement', :aggregate_failures do
        post_mutation

        expect(mutation_response['entitlement']).to be_nil
        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::RefreshEntitlement::UNAVAILABLE_ERROR
        )
      end
    end

    context 'when the user has refreshed too often' do
      before do
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:secrets_manager_entitlement_refresh, scope: { user: owner }).and_return(true)
      end

      it 'is rejected without calling CDot' do
        post_mutation

        expect_graphql_errors_to_include('This endpoint has been requested too many times')
        expect(client).not_to have_received(:secrets_manager_trial)
      end
    end

    context 'when targeting a subgroup' do
      let(:target_group) { subgroup }

      it 'returns a resource not available error' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is only a maintainer' do
    let(:current_user) { maintainer }

    it_behaves_like 'a mutation on an unauthorized resource'
  end

  context 'when the current user is not a member' do
    let(:current_user) { non_member }

    it_behaves_like 'a mutation on an unauthorized resource'
  end
end
