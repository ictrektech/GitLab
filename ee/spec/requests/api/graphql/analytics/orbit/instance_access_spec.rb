# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.orbit.access', :enable_admin_mode, feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  let(:current_user) { admin }
  let(:current_license) { ::License.current || build(:license) }
  let(:fields) { 'state reason trial { state }' }
  let(:query) { graphql_query_for(:orbit, {}, "access { #{fields} }") }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_config(knowledge_graph: { 'enabled' => true })
    allow(::License).to receive(:current).and_return(current_license)
    allow(current_license).to receive(:online_cloud_license?).and_return(true)
  end

  def access_state
    post_graphql(query, current_user: current_user)
    graphql_data_at(:orbit, :access)
  end

  context 'when the instance is unlicensed' do
    before do
      stub_licensed_features(orbit: false)
      stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: false)
    end

    it 'is unlicensed with the no_license reason' do
      expect(access_state).to include('state' => 'UNLICENSED', 'reason' => 'NO_LICENSE')
    end
  end

  context 'when the instance is licensed by plan' do
    before do
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: false)
    end

    it 'is licensed by plan' do
      expect(access_state).to include('state' => 'LICENSED', 'reason' => 'PLAN')
    end
  end

  context 'when the instance holds an active orbit_promo add-on' do
    before do
      stub_licensed_features(orbit: false)
      stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: false)
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: nil)
    end

    it 'is licensed by the promo add-on' do
      expect(access_state).to include('state' => 'LICENSED', 'reason' => 'PROMO_ADD_ON')
    end
  end

  context 'when the instance is in the trial flow' do
    before do
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: true)
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(trial)
    end

    context 'with an active trial' do
      let(:trial) do
        Gitlab::SubscriptionPortal::ProductTrialResponse.new(
          state: :trial, trial_expires_at: 10.days.from_now, credits_remaining: 120.0
        )
      end

      it 'is a trial active state and shows the trial to the admin' do
        expect(access_state).to include('state' => 'TRIAL_ACTIVE', 'trial' => { 'state' => 'ACTIVE' })
      end
    end

    context 'when the instance is eligible for a trial' do
      let(:trial) { Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :trial_eligible) }

      it 'is licensed by plan, because the license runs the queries before the promo gate' do
        expect(access_state).to include('state' => 'LICENSED', 'reason' => 'PLAN')
      end

      context 'with the promo gate' do
        before do
          stub_feature_flags(orbit_promo_access_gate: true)
        end

        it 'is a trial eligible state' do
          expect(access_state).to include('state' => 'TRIAL_ELIGIBLE')
        end
      end
    end

    context 'when the trial has ended' do
      let(:trial) do
        Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :expired, trial_expires_at: 1.day.ago)
      end

      it 'is a trial ended state with the expiry reason' do
        expect(access_state).to include('state' => 'TRIAL_ENDED', 'reason' => 'TRIAL_EXPIRED')
      end
    end

    context 'when CustomersDot does not answer' do
      let(:trial) { nil }

      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
          .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError, 'HTTP 503')
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'is licensed by plan, because the license runs the queries before the promo gate' do
        expect(access_state).to include('state' => 'LICENSED', 'reason' => 'PLAN', 'trial' => nil)
      end

      context 'with the promo gate' do
        before do
          stub_feature_flags(orbit_promo_access_gate: true)
        end

        it 'is a trial status unavailable state with no trial' do
          expect(access_state).to include('state' => 'TRIAL_STATUS_UNAVAILABLE', 'trial' => nil)
        end
      end
    end
  end

  context 'when the instance holds the orbit_promo add-on in the trial flow' do
    before do
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: nil)
    end

    it 'is licensed by the add-on and hides the trial without asking CustomersDot' do
      expect(Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

      expect(access_state).to include('state' => 'LICENSED', 'reason' => 'PROMO_ADD_ON', 'trial' => nil)
    end
  end

  context 'when the user is not an administrator' do
    let(:current_user) { user }

    before do
      stub_licensed_features(orbit: true)
    end

    it 'returns null without an error' do
      expect(access_state).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_licensed_features(orbit: true)
    end

    it 'does not expose the instance access field' do
      expect(access_state).to be_nil
    end
  end
end
