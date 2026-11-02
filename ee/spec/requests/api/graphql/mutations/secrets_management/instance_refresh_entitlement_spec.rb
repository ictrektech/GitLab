# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Refresh the Secrets Manager entitlement for the instance', :use_clean_rails_memory_store_caching,
  feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:current_user) { admin }
  let(:mutation_name) { :secrets_manager_instance_refresh_entitlement }
  let(:license) do
    instance_double(License, online_cloud_license?: true, trial?: false, feature_available?: false, plan: nil)
  end

  let(:consent_given) do
    ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible, on_demand_enabled: true)
  end

  let(:resolve_response) { ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false) }

  let(:mutation) { graphql_mutation(mutation_name, {}) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    allow(::License).to receive(:current).and_return(license)
    allow(::License).to receive(:feature_available?).and_call_original
    allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
    allow(client).to receive_messages(secrets_manager_trial: consent_given,
      secrets_manager_consumer_resolve: resolve_response)
  end

  context 'when the current user is an admin' do
    it 'returns the entitlement as CDot reports it now', :aggregate_failures do
      post_mutation

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['entitlement']).to include('state' => 'TRIAL_ELIGIBLE', 'onDemandEnabled' => true)
    end

    it 'asks CDot about the instance past its caches, with the entitlement timeout' do
      post_mutation

      expect(client).to have_received(:secrets_manager_trial)
        .with(instance_id: ::Gitlab::CurrentSettings.uuid,
          timeout: ::SecretsManagement::Entitlement::DEFAULT_HTTP_TIMEOUT_SECONDS, fresh: true)
    end

    it 'does not enroll the instance or record add-on intent', :aggregate_failures do
      post_mutation

      settings = ::Gitlab::CurrentSettings.current_application_settings
      expect(settings.secrets_manager_instance_enrolled).to be_falsey
      expect(settings.secrets_manager_instance_add_on_requested_at).to be_nil
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[enable_secrets_manager_add_on read_secrets_manager] do
      let(:user) { admin }
      let(:boundary_object) { :instance }
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
          Mutations::SecretsManagement::InstanceRefreshEntitlement::UNAVAILABLE_ERROR
        )
      end
    end

    context 'on an offline environment or legacy license' do
      let(:license) do
        instance_double(License, online_cloud_license?: false, trial?: false, feature_available?: false, plan: nil)
      end

      it 'returns the offline error without calling CDot or using the rate limit', :aggregate_failures do
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original

        post_mutation

        expect(mutation_response['entitlement']).to be_nil
        expect(mutation_response['errors']).to contain_exactly(
          Mutations::SecretsManagement::InstanceRefreshEntitlement::OFFLINE_ERROR
        )
        expect(client).not_to have_received(:secrets_manager_trial)
        expect(::Gitlab::ApplicationRateLimiter).not_to have_received(:throttled?)
          .with(:secrets_manager_entitlement_refresh, anything)
      end
    end

    context 'when the user has refreshed too often' do
      before do
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:secrets_manager_entitlement_refresh, scope: { user: admin }).and_return(true)
      end

      it 'is rejected without calling CDot' do
        post_mutation

        expect_graphql_errors_to_include('This endpoint has been requested too many times')
        expect(client).not_to have_received(:secrets_manager_trial)
      end
    end

    context 'on GitLab.com', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns a resource not available error (the instance entitlement is self-managed only)' do
        post_mutation

        expect_graphql_errors_to_include("you don't have permission")
      end
    end
  end

  context 'when the current user is not an admin' do
    let(:current_user) { user }

    it_behaves_like 'a mutation on an unauthorized resource'
  end
end
