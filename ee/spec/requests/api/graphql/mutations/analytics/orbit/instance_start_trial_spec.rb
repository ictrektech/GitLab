# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Mutation.orbitInstanceStartTrial', :enable_admin_mode, feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  let(:current_license) { ::License.current || build(:license) }
  let(:mutation) { graphql_mutation(:orbit_instance_start_trial, {}, 'access { state } errors') }
  let(:response_data) { graphql_mutation_response(:orbit_instance_start_trial) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_feature_flags(orbit_trial: true, orbit_promo_access_gate: false)
    stub_licensed_features(orbit: true)
    allow(::License).to receive(:current).and_return(current_license)
    allow(current_license).to receive(:online_cloud_license?).and_return(true)
    allow(Gitlab::CurrentSettings).to receive(:uuid).and_return('instance-uuid')
    allow(Gitlab::SubscriptionPortal::Client).to receive(:expire_product_trial_cache)
    allow(Gitlab::SubscriptionPortal::Client).to receive_messages(
      start_product_trial: Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: true),
      product_trial: Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :trial, credits_remaining: 100.0)
    )
  end

  it 'starts the instance trial for an administrator and returns the access state' do
    post_graphql_mutation(mutation, current_user: admin)

    expect(response_data['errors']).to be_empty
    expect(response_data['access']).to eq('state' => 'TRIAL_ACTIVE')
  end

  context 'when CustomersDot does not start the trial' do
    before do
      allow(Gitlab::SubscriptionPortal::Client).to receive(:start_product_trial).and_return(
        Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: false, error_code: :ineligible)
      )
    end

    it 'returns the error' do
      post_graphql_mutation(mutation, current_user: admin)

      expect(response_data['errors']).to eq(['Contact sales to get GitLab Orbit for this instance.'])
    end
  end

  context 'when the user is not an administrator' do
    it 'does not start the trial' do
      expect(Gitlab::SubscriptionPortal::Client).not_to receive(:start_product_trial)

      post_graphql_mutation(mutation, current_user: user)

      expect(graphql_errors).to be_present
    end
  end
end
