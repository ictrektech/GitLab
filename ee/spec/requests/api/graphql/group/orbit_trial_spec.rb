# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.orbit.trial', :saas, feature_category: :knowledge_graph do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let(:current_user) { owner }
  let(:trial) do
    Gitlab::SubscriptionPortal::ProductTrialResponse.new(
      state: :trial,
      trial_expires_at: Time.utc(2026, 10, 29, 23, 59, 59),
      credits_remaining: 120.0,
      credits_total: 500.0,
      offer_duration_days: 30,
      offer_credits: 100.0
    )
  end

  let(:query) do
    graphql_query_for(:group, { full_path: group.full_path }, <<~FIELDS)
      orbit { trial { state expiresOn credits { remaining total } offer { durationDays initialCredits } } }
    FIELDS
  end

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_trial: group)
    allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(trial)
  end

  it 'returns the trial state' do
    post_graphql(query, current_user: current_user)

    expect(graphql_data_at(:group, :orbit, :trial)).to eq(
      'state' => 'ACTIVE',
      'expiresOn' => '2026-10-29',
      'credits' => { 'remaining' => 120.0, 'total' => 500.0 },
      'offer' => nil
    )
  end

  describe 'offer' do
    let(:trial) do
      Gitlab::SubscriptionPortal::ProductTrialResponse.new(
        state: :trial_eligible, offer_duration_days: 30, offer_credits: 100.0
      )
    end

    it 'returns the terms when the group can start a trial' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:group, :orbit, :trial, :offer)).to eq('durationDays' => 30, 'initialCredits' => 100.0)
    end

    context 'when the user is an auditor, who can read the trial but not start it' do
      let(:current_user) { create(:user, :auditor) }

      it 'returns the trial without the terms' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:group, :orbit, :trial)).to include('state' => 'ELIGIBLE', 'offer' => nil)
      end
    end

    context 'when the group cannot start a trial' do
      where(:cdot_state, :credits_remaining, :expected_state) do
        :trial      | 10.0 | 'ACTIVE'
        :expired    | 10.0 | 'ENDED'
        :ineligible | nil  | 'NOT_ELIGIBLE'
      end

      with_them do
        let(:trial) do
          Gitlab::SubscriptionPortal::ProductTrialResponse.new(
            state: cdot_state, credits_remaining: credits_remaining, offer_duration_days: 30, offer_credits: 100.0
          )
        end

        it 'returns null' do
          post_graphql(query, current_user: current_user)

          expect(graphql_data_at(:group, :orbit, :trial)).to include('state' => expected_state, 'offer' => nil)
        end
      end
    end

    context 'when CDot does not send both terms' do
      where(:offer_duration_days, :offer_credits) do
        nil | nil
        nil | 100.0
        30  | nil
      end

      with_them do
        let(:trial) do
          Gitlab::SubscriptionPortal::ProductTrialResponse.new(
            state: :trial_eligible, offer_duration_days: offer_duration_days, offer_credits: offer_credits
          )
        end

        it 'returns null' do
          post_graphql(query, current_user: current_user)

          expect(graphql_data_at(:group, :orbit, :trial, :offer)).to be_nil
        end
      end
    end
  end

  describe 'state' do
    where(:cdot_state, :credits_remaining, :expected_state) do
      :trial_eligible | nil  | 'ELIGIBLE'
      :ineligible     | nil  | 'NOT_ELIGIBLE'
      :trial          | 10.0 | 'ACTIVE'
      :trial          | nil  | 'ACTIVE'
      :trial          | 0.0  | 'ENDED'
      :expired        | 10.0 | 'ENDED'
    end

    with_them do
      let(:trial) do
        Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: cdot_state, credits_remaining: credits_remaining)
      end

      it 'maps the CDot state' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:group, :orbit, :trial, :state)).to eq(expected_state)
      end
    end
  end

  context 'when no trial has started' do
    let(:trial) { Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :trial_eligible) }

    it 'returns null for expiresOn' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:group, :orbit, :trial, :expires_on)).to be_nil
    end
  end

  context 'when CDot does not answer' do
    let(:error) { Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('CDot unavailable: HTTP 503') }

    before do
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_raise(error)
    end

    it 'returns null for the trial and tracks the error' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, gl_namespace_id: group.id)

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:group, :orbit, :trial)).to be_nil
    end
  end

  context 'when the user is a maintainer' do
    let(:current_user) { maintainer }

    it 'returns null and does not call CDot' do
      expect(Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:group, :orbit, :trial)).to be_nil
    end
  end

  context 'when the query asks for a page of groups' do
    let_it_be(:other_group) { create(:group, owners: owner) }

    let(:query) do
      <<~GQL
        {
          a: group(fullPath: "#{group.full_path}") { orbit { trial { state } } }
          b: group(fullPath: "#{other_group.full_path}") { orbit { trial { state } } }
        }
      GQL
    end

    before do
      stub_feature_flags(orbit_trial: [group, other_group])
    end

    it 'resolves the trial for each group' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:a, :orbit, :trial, :state)).to eq('ACTIVE')
      expect(graphql_data_at(:b, :orbit, :trial, :state)).to eq('ACTIVE')
    end

    context 'when CDot is unavailable' do
      let(:error) do
        Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('CDot unavailable: HTTP 503')
      end

      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_raise(error)
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'calls CDot and tracks the error once for the whole request' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:a, :orbit, :trial)).to be_nil
        expect(graphql_data_at(:b, :orbit, :trial)).to be_nil
        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).once
        expect(Gitlab::ErrorTracking).to have_received(:track_exception).once
      end

      it 'calls CDot again in the next request' do
        2.times { post_graphql(query, current_user: current_user) }

        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).twice
      end
    end

    context 'when CDot rejects only one group' do
      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
          .with(hash_including(namespace_id: group.id))
          .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
          .with(hash_including(namespace_id: other_group.id))
          .and_return(trial)
      end

      it 'nulls only that group' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data_at(:a, :orbit, :trial)).to be_nil
        expect(graphql_data_at(:b, :orbit, :trial, :state)).to eq('ACTIVE')
      end
    end
  end

  # The frontend owned-trials query requests `first: 10`, so the field limit must stay at 10.
  context 'when the query asks for exactly 10 groups' do
    let_it_be(:other_groups) { create_list(:group, 9, owners: owner) }

    let(:query) do
      graphql_query_for(:groups, { owned_only: true, top_level_only: true, first: 10 },
        'nodes { orbit { trial { state } } }')
    end

    before do
      stub_feature_flags(orbit_trial: other_groups + [group])
    end

    it 'resolves the trial for all 10 groups' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:groups, :nodes)).to all(match('orbit' => { 'trial' => { 'state' => 'ACTIVE' } }))
      expect(graphql_data_at(:groups, :nodes).size).to eq(10)
    end
  end

  context 'when the query asks for more than 10 groups' do
    let_it_be(:groups) { create_list(:group, 10, owners: owner) }

    let(:query) do
      graphql_query_for(:groups, { owned_only: true, top_level_only: true, first: 11 },
        'nodes { orbit { trial { state } } }')
    end

    before do
      stub_feature_flags(orbit_trial: groups + [group])
    end

    it 'returns an error' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => a_string_including('trial')))
    end
  end

  context 'when the owner lists the groups they own and Orbit is off for them' do
    let(:trial) { Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :expired) }
    let(:query) do
      graphql_query_for(:groups, { owned_only: true, top_level_only: true, first: 10 },
        'nodes { orbit { trial { state } } }')
    end

    it 'returns the ended trial' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:groups, :nodes)).to contain_exactly('orbit' => { 'trial' => { 'state' => 'ENDED' } })
    end
  end
end
