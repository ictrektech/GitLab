# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.groupSecretsCount', :gitlab_secrets_manager, feature_category: :secrets_management do
  include GraphqlHelpers
  include SecretsManagement::GitlabSecretsManagerHelpers

  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }
  let(:secrets_manager) { create(:group_secrets_manager, group: group) }

  let(:query) do
    graphql_query_for('groupSecretsCount', { group_path: group.full_path })
  end

  before_all do
    group.add_owner(current_user)
  end

  before do
    enroll_instance_in_secrets_manager
  end

  shared_examples 'returns null' do
    it 'returns null with no error' do
      expect(graphql_data['groupSecretsCount']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when secrets manager is active' do
    before do
      stub_licensed_features(native_secrets_management: true)
      provision_group_secrets_manager(secrets_manager, current_user)
    end

    context 'when there are no secrets' do
      it 'returns 0' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data['groupSecretsCount']).to eq(0)
      end
    end

    context 'when there are secrets' do
      before do
        create_group_secret(
          user: current_user, group: group, name: 'GROUP_SECRET_1', value: 'v1',
          environment: 'production', protected: true
        )
        create_group_secret(
          user: current_user, group: group, name: 'GROUP_SECRET_2', value: 'v2',
          environment: 'staging', protected: false
        )
      end

      it 'returns the correct count' do
        post_graphql(query, current_user: current_user)

        expect(graphql_data['groupSecretsCount']).to eq(2)
      end
    end

    # The activation is a Sidekiq write, so the request may read the row from
    # a replica that has not replayed it yet.
    context 'when the request read a manager instance that has not replayed the activation' do
      let(:stale_secrets_manager) { SecretsManagement::GroupSecretsManager.find(secrets_manager.id) }

      before do
        allow(SecretsManagement::GroupSecretsManager.load_balancer).to receive(:primary_only?).and_return(false)
        stale_secrets_manager.status = SecretsManagement::BaseSecretsManager::STATUSES[:provisioning]
        allow_next_found_instance_of(Group) do |found_group|
          allow(found_group).to receive(:secrets_manager).and_return(stale_secrets_manager)
        end
      end

      it 'refreshes the manager and returns the count', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_data['groupSecretsCount']).to eq(0)
        expect(stale_secrets_manager).to be_active
      end
    end
  end

  context 'when secrets manager exists but is not active' do
    before do
      stub_licensed_features(native_secrets_management: true)

      create(:group_secrets_manager, :provisioning, group: group)
      post_graphql(query, current_user: current_user)
    end

    it 'returns null for an authorized user', :aggregate_failures do
      expect(Ability.allowed?(current_user, :read_secret, group)).to be(true)
      expect(graphql_data['groupSecretsCount']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when secrets manager does not exist' do
    before do
      stub_licensed_features(native_secrets_management: true)

      post_graphql(query, current_user: current_user)
    end

    it 'returns null for an authorized user', :aggregate_failures do
      expect(Ability.allowed?(current_user, :read_secret, group)).to be(true)
      expect(graphql_data['groupSecretsCount']).to be_nil
      expect(graphql_errors).to be_nil
    end
  end

  context 'when user does not have access' do
    let_it_be(:other_user) { create(:user) }

    before do
      stub_licensed_features(native_secrets_management: true)

      post_graphql(query, current_user: other_user)
    end

    it_behaves_like 'returns null'
  end
end
