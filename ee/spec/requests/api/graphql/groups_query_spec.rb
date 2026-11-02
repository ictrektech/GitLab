# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying groups with Knowledge Graph filters', feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:enabled_group) { create(:group, :private, name: 'enabled-group') }
  let_it_be(:enabled_parent_group) { create(:group, :private, name: 'enabled-parent-group') }
  let_it_be(:enabled_subgroup) { create(:group, :private, parent: enabled_parent_group) }
  let_it_be(:disabled_group) { create(:group, :private, name: 'disabled-group') }

  let(:filters) do
    {
      allAvailable: false,
      topLevelOnly: true,
      withKnowledgeGraphEnabled: true
    }
  end

  let(:query) do
    graphql_query_for(
      :groups,
      filters,
      <<~FIELDS
        nodes {
          name
          orbit { enabled }
        }
      FIELDS
    )
  end

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: enabled_group)
    create(:knowledge_graph_enabled_namespace, namespace: enabled_parent_group)
    enabled_group.add_developer(user)
    enabled_parent_group.add_developer(user)
    enabled_subgroup.add_developer(user)
    disabled_group.add_developer(user)
  end

  it 'returns only top-level member groups with Knowledge Graph enabled' do
    post_graphql(query, current_user: user)

    expect_graphql_errors_to_be_empty
    expect(graphql_data_at(:groups, :nodes)).to contain_exactly(
      a_hash_including(
        'name' => enabled_group.name,
        'orbit' => { 'enabled' => true }
      ),
      a_hash_including(
        'name' => enabled_parent_group.name,
        'orbit' => { 'enabled' => true }
      )
    )
  end

  describe 'resolving startOrbitTrial for owned groups' do
    let_it_be(:owned_group) { create(:group, owners: user) }

    let(:query) do
      graphql_query_for(
        :groups,
        { ownedOnly: true, topLevelOnly: true },
        'nodes { userPermissions { startOrbitTrial } }'
      )
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_licensed_features(orbit: true)
    end

    it 'reads the trial enrollment for every group in a single query' do
      create(:group, owners: user)

      recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }
      enrollment_queries = recorder.log.count { |sql| sql.include?('orbit_namespace_enrollments') }

      expect(enrollment_queries).to be <= 1
    end
  end

  describe 'resolving orbit trial offer for owned groups', :saas do
    let_it_be(:owned_groups) { create_list(:group, 2, owners: user) }

    let(:query) do
      graphql_query_for(
        :groups,
        { ownedOnly: true, topLevelOnly: true },
        'nodes { orbit { trial { offer { durationDays } } } }'
      )
    end

    before do
      stub_licensed_features(orbit: true)
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(
        Gitlab::SubscriptionPortal::ProductTrialResponse.new(
          state: :trial_eligible, offer_duration_days: 30, offer_credits: 100.0
        )
      )
    end

    it 'reads the trial enrollment for every group in a single query' do
      recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }
      enrollment_queries = recorder.log.count { |sql| sql.include?('orbit_namespace_enrollments') }

      expect(graphql_data_at(:groups, :nodes, :orbit, :trial, :offer).compact.size).to eq(2)
      expect(enrollment_queries).to eq(1)
    end
  end

  describe 'resolving orbit enabledAt for owned groups' do
    let_it_be(:owned_groups) { create_list(:group, 2, owners: user) }

    let(:query) do
      graphql_query_for(
        :groups,
        { ownedOnly: true, topLevelOnly: true },
        'nodes { orbit { enabledAt } }'
      )
    end

    before_all do
      owned_groups.each { |group| create(:knowledge_graph_enabled_namespace, namespace: group) }
    end

    before do
      allow(::Analytics::KnowledgeGraph).to receive(:status_accessible_for_request?).with(user).and_return(true)
    end

    it 'reads the enabled namespaces for every group in a single query' do
      recorder = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: user) }
      enabled_namespace_queries = recorder.log.count { |sql| sql.include?('knowledge_graph_enabled_namespaces') }

      expect(graphql_data_at(:groups, :nodes, :orbit, :enabled_at).compact.size).to eq(2)
      expect(enabled_namespace_queries).to eq(1)
    end
  end
end
