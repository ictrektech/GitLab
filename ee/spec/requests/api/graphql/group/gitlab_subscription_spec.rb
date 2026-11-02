# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying gitlabSubscription on a group', :saas, feature_category: :consumables_cost_management do
  include GraphqlHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:group) { create(:group, owners: owner) }

  let(:current_user) { owner }
  let(:query) do
    graphql_query_for(:group, { fullPath: group.full_path }, 'gitlabSubscription { active }')
  end

  subject(:gitlab_subscription) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:group, :gitlab_subscription)
  end

  context 'when the group has an active paid subscription' do
    before_all do
      create(:gitlab_subscription, :premium, namespace: group)
    end

    it { is_expected.to eq('active' => true) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', %i[read_group read_gitlab_subscription] do
      let(:user) { owner }
      let(:boundary_object) { group }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end

    context 'when the user is not an owner' do
      let_it_be(:maintainer) { create(:user, maintainer_of: group) }

      let(:current_user) { maintainer }

      it { is_expected.to be_nil }
    end

    context 'when GitLab.com subscriptions are not available' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to be_nil }
    end
  end

  context 'when the group has an expired paid subscription' do
    before_all do
      create(:gitlab_subscription, :premium, :expired, namespace: group)
    end

    it { is_expected.to eq('active' => false) }
  end

  context 'when the group has no subscription' do
    it { is_expected.to be_nil }
  end

  describe 'querying a list of groups' do
    let(:query) do
      graphql_query_for(
        :groups,
        { ownedOnly: true, topLevelOnly: true },
        'nodes { gitlabSubscription { active } }'
      )
    end

    before_all do
      create(:gitlab_subscription, :premium, namespace: group)
      create(:gitlab_subscription, :ultimate, :expired, namespace: create(:group, owners: owner))
    end

    it 'loads the subscriptions for every group in a single query' do
      recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      subscription_queries = recorder.log.count { |sql| sql.include?('FROM "gitlab_subscriptions"') }

      expect(graphql_data_at(:groups, :nodes, :gitlab_subscription, :active)).to contain_exactly(true, false)
      expect(subscription_queries).to eq(1)
    end
  end
end
