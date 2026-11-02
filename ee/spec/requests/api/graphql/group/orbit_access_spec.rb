# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.orbit.access', :saas, :clean_gitlab_redis_rate_limiting,
  feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:member) { create(:user, developer_of: group) }
  let_it_be(:admin) { create(:admin) }

  let(:current_user) { owner }
  let(:trial) do
    Gitlab::SubscriptionPortal::ProductTrialResponse.new(
      state: :trial, trial_expires_at: Time.utc(2026, 10, 29, 23, 59, 59), credits_remaining: 120.0
    )
  end

  let(:access_fields) do
    'orbit { access { state reason turnOnDenialReason trial { state } } }'
  end

  let(:query) do
    graphql_query_for(:group, { full_path: group.full_path }, access_fields)
  end

  before do
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_trial: group)
    allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(trial)
  end

  context 'as the group owner' do
    it 'returns the access state and the trial' do
      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit, :access)).to include(
        'state' => 'TRIAL_ACTIVE', 'reason' => nil, 'trial' => { 'state' => 'ACTIVE' }
      )
    end
  end

  context 'when the group can start a trial' do
    let(:trial) do
      Gitlab::SubscriptionPortal::ProductTrialResponse.new(
        state: :trial_eligible, offer_duration_days: 30, offer_credits: 100.0
      )
    end

    let(:access_fields) { 'orbit { access { trial { offer { durationDays initialCredits } } } }' }

    it 'returns the terms of the trial' do
      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit, :access, :trial, :offer)).to eq(
        'durationDays' => 30, 'initialCredits' => 100.0
      )
    end

    it 'returns no terms to a beta group, which cannot start a trial during the beta' do
      stub_feature_flags(orbit_promo_access_gate: false)
      create(:orbit_namespace_enrollment, :beta, namespace: group)

      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit, :access, :trial)).to eq('offer' => nil)
    end
  end

  context 'as an instance admin', :enable_admin_mode do
    it 'reads the state like an owner' do
      post_graphql(query, current_user: admin)

      expect(graphql_data_at(:group, :orbit, :access, :state)).to eq('TRIAL_ACTIVE')
    end
  end

  context 'as a group member below owner' do
    it 'returns no access state and never calls CustomersDot' do
      expect(Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

      post_graphql(query, current_user: member)

      expect(graphql_data_at(:group, :orbit, :access)).to be_nil
    end
  end

  context 'when CustomersDot does not answer and Orbit is on' do
    let_it_be(:enabled_namespace) do
      create(:knowledge_graph_enabled_namespace, namespace: group)
    end

    let(:error) { Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('HTTP 503') }
    let(:query) do
      graphql_query_for(:group, { full_path: group.full_path }, 'orbit { enabled access { state } }')
    end

    before do
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_raise(error)
    end

    it 'reports the trial status as unavailable without an error' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, gl_namespace_id: group.id)

      post_graphql(query, current_user: owner)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:group)).to eq(
        'orbit' => { 'enabled' => true, 'access' => { 'state' => 'TRIAL_STATUS_UNAVAILABLE' } }
      )
    end
  end

  describe 'Group.orbit.trial' do
    let_it_be(:auditor) { create(:auditor) }

    let(:query) do
      graphql_query_for(:group, { full_path: group.full_path }, 'orbit { trial { state } access { state } }')
    end

    before do
      stub_feature_flags(orbit_trial: group)
    end

    it 'returns the trial to an Owner' do
      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit)).to eq(
        'trial' => { 'state' => 'ACTIVE' }, 'access' => { 'state' => 'TRIAL_ACTIVE' }
      )
    end

    it 'returns the trial but not the access to an Auditor' do
      post_graphql(query, current_user: auditor)

      expect(graphql_data_at(:group, :orbit)).to eq('trial' => { 'state' => 'ACTIVE' }, 'access' => nil)
    end

    it 'returns null for a subgroup and a project without calling CustomersDot' do
      subgroup = create(:group, :private, parent: group)
      project = create(:project, :private, group: group)
      query = <<~GRAPHQL
        query {
          group(fullPath: "#{subgroup.full_path}") { orbit { trial { state } } }
          project(fullPath: "#{project.full_path}") { orbit { trial { state } } }
        }
      GRAPHQL

      expect(Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit, :trial)).to be_nil
      expect(graphql_data_at(:project, :orbit, :trial)).to be_nil
    end

    it 'returns null when CustomersDot does not answer' do
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
        .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('HTTP 503'))

      post_graphql(query, current_user: owner)

      expect(graphql_data_at(:group, :orbit, :trial)).to be_nil
    end
  end

  context 'with Group.orbit.access' do
    let_it_be(:other_groups) { create_list(:group, 9, owners: owner) }

    let(:groups_args) { { owned_only: true, top_level_only: true, first: 10 } }
    let(:query) do
      graphql_query_for(:orbit, {}, query_graphql_field(:groups, groups_args, 'nodes { orbit { access { state } } }'))
    end

    before do
      stub_feature_flags(orbit_trial: other_groups + [group])
    end

    it 'resolves the access state for all 10 groups' do
      post_graphql(query, current_user: owner)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:orbit, :groups, :nodes))
        .to all(match('orbit' => { 'access' => { 'state' => 'TRIAL_ACTIVE' } }))
      expect(graphql_data_at(:orbit, :groups, :nodes).size).to eq(10)
    end

    it 'reads the enabled namespaces and enrollments of all groups in one query each' do
      other_groups.first(3).each do |other_group|
        create(:knowledge_graph_enabled_namespace, namespace: other_group)
        create(:orbit_namespace_enrollment, namespace: other_group)
      end

      recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: owner) }

      expect(recorder.log.count { |sql| sql.include?('FROM "knowledge_graph_enabled_namespaces"') }).to eq(1)
      expect(recorder.log.count { |sql| sql.include?('FROM "orbit_namespace_enrollments"') }).to eq(1)
    end

    context 'when CustomersDot does not answer' do
      let(:query) do
        graphql_query_for(:orbit, {},
          query_graphql_field(:groups, groups_args, 'nodes { orbit { trial { state } access { state } } }'))
      end

      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
          .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('HTTP 503'))
      end

      it 'calls CustomersDot once for both fields and all groups' do
        post_graphql(query, current_user: owner)

        expect(graphql_data_at(:orbit, :groups, :nodes)).to all(
          match('orbit' => { 'trial' => nil, 'access' => { 'state' => 'TRIAL_STATUS_UNAVAILABLE' } })
        )
        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).once
      end
    end

    context 'when the query asks for more than 10 groups' do
      let(:groups_args) { { owned_only: true, top_level_only: true, first: 11 } }

      it 'returns an error' do
        create(:group, owners: owner)

        post_graphql(query, current_user: owner)

        expect(graphql_errors).to include(a_hash_including('message' => a_string_including('access')))
      end
    end
  end
end
