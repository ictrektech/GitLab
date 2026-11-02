# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::Catalog::ItemConsumer::Delete, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project, :in_group, maintainers: maintainer) }
  let_it_be_with_reload(:item_consumer) { create(:ai_catalog_item_consumer, project: project) }

  let(:current_user) { maintainer }
  let(:mutation) { graphql_mutation(:ai_catalog_item_consumer_delete, params) }
  let(:params) do
    {
      id: item_consumer.to_global_id
    }
  end

  subject(:execute) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    enable_ai_catalog
  end

  shared_examples 'an authorization failure' do
    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not delete the item consumer' do
      expect { execute }.not_to change { Ai::Catalog::ItemConsumer.count }
    end
  end

  context 'when user is a developer' do
    let(:current_user) { create(:user).tap { |user| project.add_developer(user) } }

    it_behaves_like 'an authorization failure'
  end

  context 'when the item consumer does not exist' do
    let(:params) do
      {
        id: Gitlab::GlobalId.build(model_name: 'Ai::Catalog::ItemConsumer', id: non_existing_record_id)
      }
    end

    it_behaves_like 'an authorization failure'
  end

  context 'when destroy service fails' do
    before do
      allow_next_instance_of(::Ai::Catalog::ItemConsumers::DestroyService) do |service|
        allow(service).to receive(:item_consumer).and_return(item_consumer)
      end

      allow(item_consumer).to receive(:destroy).and_return(false)
      item_consumer.errors.add(:base, 'Deletion failed')
    end

    it 'returns the service error message' do
      execute

      expect(graphql_data_at(:ai_catalog_item_consumer_delete, :errors)).to contain_exactly('Deletion failed')
      expect(graphql_data_at(:ai_catalog_item_consumer_delete, :success)).to be(false)
    end
  end

  context 'when user has a custom role with admin_ai_catalog_item_consumer' do
    let_it_be(:custom_role_user) { create(:user) }
    let_it_be(:custom_role) do
      create(:member_role, :guest, :admin_ai_catalog_item_consumer, namespace: project.group)
    end

    let_it_be(:custom_role_membership) do
      create(:project_member, :guest, member_role: custom_role, user: custom_role_user, project: project)
    end

    let(:current_user) { custom_role_user }

    before do
      stub_licensed_features(custom_roles: true)
    end

    it 'destroys the item consumer' do
      expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(-1)
    end
  end

  context 'when destroy service succeeds' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_ai_catalog_item_consumer do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:authz_mutation) { graphql_mutation(:ai_catalog_item_consumer_delete, params, 'errors') }
      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end

    it 'destroys the item consumer and returns a success response' do
      expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(-1)
      expect(graphql_data_at(:ai_catalog_item_consumer_delete, :success)).to be(true)
    end
  end

  context 'when the item consumer belongs to a group' do
    let_it_be(:group) { create(:group, owners: maintainer) }
    let_it_be_with_reload(:group_item_consumer) { create(:ai_catalog_item_consumer, group: group) }

    let(:params) do
      {
        id: group_item_consumer.to_global_id
      }
    end

    it 'destroys the item consumer and returns a success response' do
      expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(-1)
      expect(graphql_data_at(:ai_catalog_item_consumer_delete, :success)).to be(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_ai_catalog_item_consumer do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:authz_mutation) { graphql_mutation(:ai_catalog_item_consumer_delete, params, 'errors') }
      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end

  describe 'rate limiting', :clean_gitlab_redis_rate_limiting, :freeze_time do
    def exhaust_rate_limit_for(user)
      30.times do
        Gitlab::ApplicationRateLimiter.throttled?(:ai_catalog_item_consumer_delete, scope: { user: user })
      end
    end

    context 'when the rate limit is exceeded' do
      before do
        exhaust_rate_limit_for(current_user)
      end

      it 'returns an error and does not delete the item consumer' do
        expect { execute }.not_to change { Ai::Catalog::ItemConsumer.count }

        expect(graphql_data_at(:ai_catalog_item_consumer_delete, :success)).to be(false)
        expect(graphql_data_at(:ai_catalog_item_consumer_delete, :errors)).to contain_exactly(
          'You have disabled items too many times. Try again in a minute.'
        )
      end

      it 'logs the throttled request with the user to the auth log' do
        expect(Gitlab::AuthLogger).to receive(:error).with(
          hash_including(
            message: 'Application_Rate_Limiter_Request',
            env: :ai_catalog_item_consumer_delete_request_limit,
            user_id: current_user.id,
            username: current_user.username
          )
        )

        execute
      end
    end

    context 'when another user has exceeded the rate limit' do
      let_it_be(:another_user) { create(:user) }

      before do
        exhaust_rate_limit_for(another_user)
      end

      it 'still deletes the item consumer for the current user' do
        expect { execute }.to change { Ai::Catalog::ItemConsumer.count }.by(-1)

        expect(graphql_data_at(:ai_catalog_item_consumer_delete, :success)).to be(true)
      end
    end
  end
end
