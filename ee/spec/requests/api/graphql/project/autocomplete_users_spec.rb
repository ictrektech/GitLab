# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'autocomplete users for a project', feature_category: :team_planning do
  include GraphqlHelpers
  include Ai::Catalog::FlowFactoryHelpers

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :repository, :public, group: group) }
  let_it_be(:current_user) { create(:user, guest_of: project) }

  let(:params) { {} }
  let(:query) do
    graphql_query_for(
      'project',
      { 'fullPath' => project.full_path },
      query_graphql_field('autocompleteUsers', params, 'id username')
    )
  end

  describe 'N+1 queries with merge request interaction', :use_sql_query_cache do
    let_it_be_with_reload(:merge_request) { create(:merge_request, source_project: project) }
    let_it_be_with_reload(:protected_branch) do
      create(:protected_branch, project: project, name: merge_request.target_branch)
    end

    let_it_be(:approval_rule) do
      create(:approval_merge_request_rule, merge_request: merge_request)
    end

    let(:query) do
      get_graphql_query_as_string(
        'graphql_shared/queries/project_autocomplete_users_with_mr_permissions.query.graphql',
        ee: true
      )
    end

    let(:variables) do
      {
        search: '',
        fullPath: project.full_path,
        mergeRequestId: merge_request.to_global_id.to_s
      }
    end

    before do
      stub_licensed_features(merge_request_approvers: true, admin_merge_request_approvers_rules: true)
    end

    it 'does not have N+1 queries' do
      post_graphql(query, current_user: current_user, variables: variables) # warm-up

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(query, current_user: current_user, variables: variables)
      end

      create_list(:user, 3, developer_of: project)

      expect do
        post_graphql(query, current_user: current_user, variables: variables)
      end.not_to exceed_all_query_limit(control).with_threshold(4)
    end
  end

  describe 'duoStatus field' do
    let(:query) do
      graphql_query_for(
        'project',
        { 'fullPath' => project.full_path },
        query_graphql_field(
          'autocompleteUsers',
          params,
          <<~QUERY
          username
          duoStatus {
            disabled
            disabledReason
          }
          QUERY
        )
      )
    end

    let(:user_data) { graphql_data.dig('project', 'autocompleteUsers') }

    context 'when user type is human' do
      let!(:user) { current_user }

      it 'returns null' do
        post_graphql(query, current_user: current_user)

        expect(user_data[0]['username']).to eq(user.username)
        expect(user_data[0]['duoStatus']).to be_nil
      end
    end

    context 'when user is a regular service account' do
      let!(:user) do
        create(:user, :service_account, guest_of: project, composite_identity_enforced: false)
      end

      it 'returns null' do
        post_graphql(query, current_user: current_user)

        expect(user_data[0]['username']).to eq(user.username)
        expect(user_data[0]['duoStatus']).to be_nil
      end
    end

    context 'when user is a composite identity user' do
      let_it_be(:user) do
        create(:composite_identity_service_account_for_project, project: project)
      end

      let(:usage_quota_result) do
        ServiceResponse.success
      end

      before do
        allow_next_instance_of(
          ::Ai::UsageQuotaService,
          user: current_user
        ) do |instance|
          allow(instance).to receive(:execute).and_return(usage_quota_result)
        end
      end

      context 'and usage quota is not exceeded' do
        it 'returns the Duo status' do
          post_graphql(query, current_user: current_user)

          expect(user_data[0]['username']).to eq(user.username)
          expect(user_data[0]['duoStatus']).to match(
            'disabled' => false,
            'disabledReason' => ''
          )
        end
      end

      context 'and usage quota is exceeded' do
        let(:usage_quota_result) do
          ServiceResponse.error(reason: :usage_quota_exceeded, message: 'No credits available')
        end

        it 'returns the Duo status' do
          post_graphql(query, current_user: current_user)

          expect(user_data[0]['username']).to eq(user.username)
          expect(user_data[0]['duoStatus']).to match(
            'disabled' => true,
            'disabledReason' => 'Unavailable - no credits'
          )
        end
      end

      context 'when flowTriggerEvents are requested' do
        let(:usage_quota_result) do
          ServiceResponse.error(reason: :usage_quota_exceeded, message: 'No credits available')
        end

        let(:query_with_flow_trigger_events) do
          graphql_query_for(
            'project',
            { 'fullPath' => project.full_path },
            query_graphql_field(
              'autocompleteUsers',
              params,
              <<~QUERY
              username
              duoStatus {
                disabled
                disabledReason
                flowTriggerEvents
              }
              QUERY
            )
          )
        end

        context 'when triggers are for item consumers' do
          before do
            create_flow_configuration_for_project(project, user, [1, 2])
          end

          it 'does not add trigger or item consumer queries for more service accounts' do
            trigger_queries = ->(recorder) do
              recorder.log.count { |query| query.match?(/FROM "(ai_flow_triggers|ai_catalog_item_consumers)"/) }
            end

            control = ActiveRecord::QueryRecorder.new do
              post_graphql(query_with_flow_trigger_events, current_user: current_user)
            end

            other_service_account = create(:composite_identity_service_account_for_project, project: project)
            create_flow_configuration_for_project(project, other_service_account, [0])

            recorder = ActiveRecord::QueryRecorder.new do
              post_graphql(query_with_flow_trigger_events, current_user: current_user)
            end

            expect(trigger_queries.call(control)).to be_positive
            expect(trigger_queries.call(recorder)).to eq(trigger_queries.call(control))

            other_node = user_data.find { |node| node['username'] == other_service_account.username }
            expect(other_node.dig('duoStatus', 'flowTriggerEvents')).to eq(%w[MENTION])

            user_node = user_data.find { |node| node['username'] == user.username }
            expect(user_node['duoStatus']).to match(
              'disabled' => true,
              'disabledReason' => 'Unavailable - no credits',
              'flowTriggerEvents' => %w[ASSIGN ASSIGN_REVIEWER]
            )
          end
        end

        context 'when triggers are inherited from the root group' do
          def create_service_account_with_inherited_trigger
            service_account = create(:composite_identity_service_account_for_project, project: project)

            consumer = create(:ai_catalog_item_consumer, :inheritance,
              group: group, service_account: service_account)

            create(:ai_flow_trigger, :for_inheritance_consumer,
              group: group,
              ai_catalog_item_consumer: consumer,
              event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])

            service_account
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

            events = user_data.filter_map { |node| node.dig('duoStatus', 'flowTriggerEvents') }
            expect(events).to include(%w[MENTION])
          end
        end

        context 'when triggers are not for item consumers' do
          before do
            create(:ai_flow_trigger, project: project, event_types: [0], user: user)
          end

          it 'returns the triggers' do
            post_graphql(query_with_flow_trigger_events, current_user: current_user)

            expect(user_data[0]['username']).to eq(user.username)
            expect(user_data[0]['duoStatus']).to match(
              'disabled' => true,
              'disabledReason' => 'Unavailable - no credits',
              'flowTriggerEvents' => %w[MENTION]
            )
          end
        end
      end
    end
  end

  context 'when the project is in a personal namespace' do
    let_it_be(:owner) { create(:user, :with_namespace) }
    let_it_be(:personal_project) { create(:project, :public, namespace: owner.namespace) }

    it 'returns flow trigger events without errors' do
      query = graphql_query_for(
        'project',
        { 'fullPath' => personal_project.full_path },
        query_graphql_field('autocompleteUsers', {}, 'username duoStatus { flowTriggerEvents }')
      )

      post_graphql(query, current_user: owner)

      expect(graphql_errors).to be_nil
    end
  end
end
