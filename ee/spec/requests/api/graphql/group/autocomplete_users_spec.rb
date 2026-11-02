# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'autocomplete users for a group', feature_category: :ai_agents do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, guest_of: group) }

  let(:user_data) { graphql_data.dig('group', 'autocompleteUsers') }

  let(:query_with_flow_trigger_events) do
    graphql_query_for(
      'group',
      { 'fullPath' => group.full_path },
      query_graphql_field(
        'autocompleteUsers',
        {},
        <<~QUERY
        username
        duoStatus {
          flowTriggerEvents
        }
        QUERY
      )
    )
  end

  before do
    allow_next_instance_of(::Ai::UsageQuotaService, user: current_user) do |instance|
      allow(instance).to receive(:execute).and_return(ServiceResponse.success)
    end
  end

  describe 'inherited flow trigger events' do
    def create_service_account_with_inherited_trigger
      service_account = create(:user, :service_account,
        guest_of: group,
        composite_identity_enforced: true,
        provisioned_by_group: group)

      consumer = create(:ai_catalog_item_consumer, :inheritance,
        group: group, service_account: service_account)

      create(:ai_flow_trigger, :for_inheritance_consumer,
        group: group,
        ai_catalog_item_consumer: consumer,
        event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

      service_account
    end

    it 'returns inherited flow trigger events for service accounts' do
      create_service_account_with_inherited_trigger

      post_graphql(query_with_flow_trigger_events, current_user: current_user)

      sa_data = user_data.filter_map { |node| node.dig('duoStatus', 'flowTriggerEvents') }
      expect(sa_data).to include(%w[MENTION])
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it 'does not return inherited flow trigger events' do
        create_service_account_with_inherited_trigger

        post_graphql(query_with_flow_trigger_events, current_user: current_user)

        sa_data = user_data.filter_map { |node| node.dig('duoStatus', 'flowTriggerEvents') }
        expect(sa_data).not_to include(%w[MENTION])
      end
    end

    it 'does not load flow triggers when flowTriggerEvents is not selected' do
      create_service_account_with_inherited_trigger

      expect(Types::Users::DuoStatusType).not_to receive(:flow_trigger_events_by_user)

      query = graphql_query_for(
        'group',
        { 'fullPath' => group.full_path },
        query_graphql_field('autocompleteUsers', {}, 'username duoStatus { disabled }')
      )

      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
    end

    it 'does not issue a query per service account' do
      create_service_account_with_inherited_trigger

      post_graphql(query_with_flow_trigger_events, current_user: current_user) # warm-up

      control = ActiveRecord::QueryRecorder.new do
        post_graphql(query_with_flow_trigger_events, current_user: current_user)
      end

      create_service_account_with_inherited_trigger
      create_service_account_with_inherited_trigger

      expect do
        post_graphql(query_with_flow_trigger_events, current_user: current_user)
      end.not_to exceed_query_limit(control)
    end
  end
end
