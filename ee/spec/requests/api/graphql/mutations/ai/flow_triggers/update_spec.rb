# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowTriggers::Update, feature_category: :dap_triggers do
  include GraphqlHelpers
  include Ai::Catalog::TestHelpers

  let_it_be(:project) { create(:project, :repository, :in_group, maintainers: [service_account]) }
  let_it_be(:group_owner) { create(:user, owner_of: project.group) }
  let_it_be(:service_account) { create(:service_account, provisioned_by_group: project.root_ancestor) }

  let_it_be_with_reload(:trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:subscription_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_core, :self_managed) }
  let_it_be(:original) { trigger.attributes.dup }

  let(:current_user) { group_owner }
  let(:mutation) { graphql_mutation(:ai_flow_trigger_update, params) }
  let(:description) { 'New' }
  let(:event_types) { [Ai::FlowTrigger::EVENT_TYPES[:mention]] }
  let(:params) do
    {
      id: trigger.to_global_id,
      user_id: service_account.to_global_id,
      description: description,
      event_types: event_types,
      config_path: '.gitlab/duo_agents.yml'
    }
  end

  subject(:execute) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    ::Ai::Setting.for_organization(current_organization).update!(duo_core_features_enabled: true)
    stub_ee_application_setting(allow_top_level_group_owners_to_create_service_accounts: true,
      duo_features_enabled: true)
  end

  shared_examples 'an authorization failure' do
    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not modify the trigger' do
      expect { execute }.not_to change { trigger.attributes }
    end
  end

  context 'when user does not have permission' do
    let(:current_user) { create(:user).tap { |user| project.add_developer(user) } }

    it_behaves_like 'an authorization failure'
  end

  context 'when graphql params are invalid' do
    let(:params) { super().merge(user_id: 'gid://gitlab/Project/1') }

    it 'returns the validation error' do
      execute

      expect(graphql_errors.first['message']).to include('does not represent an instance of User')
    end
  end

  context 'when model params are invalid' do
    let(:description) { 'a' * 256 }

    it 'returns the validation error' do
      execute

      expect(graphql_data_at(:ai_flow_trigger_update, :errors).first).to include(
        'Description is too long (maximum is 255 characters)'
      )
      expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to be_nil
    end
  end

  it 'creates a flow trigger with expected data' do
    expect { execute }.to change { trigger.reload.attributes }.from(
      a_hash_including(
        'description' => original['description'],
        'user_id' => original['user_id'],
        'config_path' => original['config_path']
      )
    ).to(
      a_hash_including(
        'description' => 'New',
        'user_id' => service_account.id,
        'config_path' => '.gitlab/duo_agents.yml'
      )
    )
  end

  it 'returns the new trigger' do
    execute

    expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to match a_hash_including(
      'description' => description,
      'eventTypes' => event_types,
      'configPath' => '.gitlab/duo_agents.yml',
      'configUrl' => "/#{project.full_path}/-/blob/#{project.default_branch}/.gitlab/duo_agents.yml",
      'project' => a_hash_including('id' => project.to_global_id.to_s),
      'user' => a_hash_including('id' => service_account.to_global_id.to_s)
    )
  end

  context 'when toggling the active flag' do
    let(:params) { { id: trigger.to_global_id, active: false } }

    it 'deactivates the trigger and returns the new state' do
      expect { execute }.to change { trigger.reload.active }.from(true).to(false)

      expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger, :active)).to be(false)
    end

    context 'when re-activating an inactive trigger' do
      let(:params) { { id: trigger.to_global_id, active: true } }

      before do
        trigger.update!(active: false)
      end

      it 'activates the trigger' do
        expect { execute }.to change { trigger.reload.active }.from(false).to(true)
      end
    end

    context 'when active is not provided' do
      let(:params) { { id: trigger.to_global_id, description: 'New' } }

      it 'does not change the active flag' do
        expect { execute }.not_to change { trigger.reload.active }.from(true)
      end
    end
  end

  context 'with granular token permissions' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_flow_trigger do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:authz_mutation) { graphql_mutation(:ai_flow_trigger_update, params, 'errors') }
      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end

  context 'when on-finish settings are provided' do
    let(:query) do
      <<~MUTATION
        mutation($input: AiFlowTriggerUpdateInput!) {
          aiFlowTriggerUpdate(input: $input) {
            aiFlowTrigger { id statusOnFinish readyMergeRequestsOnFinish }
            errors
          }
        }
      MUTATION
    end

    let(:input) do
      {
        id: trigger.to_global_id.to_s,
        eventTypes: [Ai::FlowTrigger::EVENT_TYPES[:work_item]],
        filter: {
          'work_item' => {
            'rules' => [
              { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
              { 'field' => 'status.name', 'operator' => 'in', 'value' => ['Planning'] }
            ]
          }
        },
        statusOnFinish: 'In review',
        readyMergeRequestsOnFinish: true
      }
    end

    subject(:execute) { post_graphql(query, current_user: current_user, variables: { input: input }.to_json) }

    it 'persists and returns the settings' do
      execute

      expect(trigger.reload).to have_attributes(status_on_finish: 'In review', ready_merge_requests_on_finish: true)
      expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger))
        .to include('statusOnFinish' => 'In review', 'readyMergeRequestsOnFinish' => true)
    end

    context 'when readyMergeRequestsOnFinish is null' do
      let(:input) { super().merge(readyMergeRequestsOnFinish: nil) }

      it 'returns an error and keeps the setting' do
        execute

        expect(graphql_errors.to_s).to include('readyMergeRequestsOnFinish')
        expect(trigger.reload.ready_merge_requests_on_finish).to be(false)
      end
    end

    context 'when the trigger does not use the work item event type' do
      let(:input) { super().merge(eventTypes: [Ai::FlowTrigger::EVENT_TYPES[:mention]], filter: {}) }

      it 'returns the validation error' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :errors).first).to include('Status changed as its only action')
      end
    end

    context 'when the status is longer than 255 characters' do
      let(:input) { super().merge(statusOnFinish: 'a' * 256) }

      it 'returns the validation error' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :errors).first).to include('Status on finish')
      end
    end
  end

  context 'when goals are provided' do
    # Build the query by hand and pass the variables as a raw JSON string so that
    # `prepare_variables` does not camelize the event-type keys inside the
    # JSON-typed `goals` argument.
    let(:goals) { { 'mention' => 'Summarise the discussion so far.' } }

    let(:query) do
      <<~MUTATION
        mutation($input: AiFlowTriggerUpdateInput!) {
          aiFlowTriggerUpdate(input: $input) {
            aiFlowTrigger { id goals }
            errors
          }
        }
      MUTATION
    end

    let(:input) do
      {
        id: trigger.to_global_id.to_s,
        description: description,
        eventTypes: event_types,
        goals: goals
      }
    end

    subject(:execute) { post_graphql(query, current_user: current_user, variables: { input: input }.to_json) }

    it 'persists the goals on the trigger' do
      execute

      expect(trigger.reload.goals).to eq(goals)
    end

    it 'returns the goals on the response' do
      execute

      expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger, :goals)).to eq(goals)
    end

    context 'when the argument is omitted' do
      let(:input) { super().except(:goals) }

      before do
        trigger.update!(goals: { 'mention' => 'Keep this one.' })
      end

      it 'leaves the stored goals alone' do
        execute

        expect(trigger.reload.goals).to eq({ 'mention' => 'Keep this one.' })
      end
    end

    context 'when the argument is null' do
      let(:goals) { nil }

      before do
        trigger.update!(goals: { 'mention' => 'Clear this one.' })
      end

      it 'clears the goals' do
        execute

        expect(trigger.reload.goals).to eq({})
      end
    end

    context 'when the feature flag is disabled' do
      let(:goals) { { 'mention' => 'Changed goal.' } }

      before do
        trigger.update!(goals: { 'mention' => 'Stored goal.' })
        stub_feature_flags(ai_flow_trigger_goals: false)
      end

      it 'refuses the goals and leaves the stored ones alone' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :errors).first).to include('are not available')
        expect(trigger.reload.goals).to eq({ 'mention' => 'Stored goal.' })
      end
    end
  end

  context 'when updating catalog item configuration' do
    let_it_be(:parent_item_consumer) do
      create(
        :ai_catalog_item_consumer, :parent_item_consumer, group: project.root_ancestor, service_account: service_account
      )
    end

    let_it_be(:item_consumer1) do
      create(
        :ai_catalog_item_consumer,
        :child_item_consumer,
        project: project,
        parent_item_consumer: parent_item_consumer,
        item: parent_item_consumer.item
      )
    end

    let_it_be(:item_consumer2) { create(:ai_catalog_item_consumer, :child_item_consumer, project: project) }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog).and_return(true)
      stub_validate_config_service
    end

    context 'when switching from config_path to catalog item' do
      let_it_be_with_reload(:config_trigger) do
        create(:ai_flow_trigger, project: project, user: service_account, config_path: 'original/config.yml')
      end

      let(:params) do
        {
          id: config_trigger.to_global_id,
          user_id: service_account.to_global_id,
          description: description,
          event_types: event_types,
          config_path: nil,
          ai_catalog_item_consumer_id: item_consumer1.to_global_id
        }
      end

      it 'updates to use catalog item' do
        execute

        config_trigger.reload
        expect(config_trigger).to have_attributes(
          description: description,
          user_id: nil,
          event_types: event_types,
          config_path: nil,
          ai_catalog_item_consumer_id: item_consumer1.id
        )
      end

      it 'returns the updated trigger with catalog item data' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to match a_hash_including(
          'description' => description,
          'eventTypes' => event_types,
          'configPath' => nil,
          'configUrl' => nil,
          'aiCatalogItemConsumer' => a_hash_including('id' => item_consumer1.to_global_id.to_s),
          'project' => a_hash_including('id' => project.to_global_id.to_s),
          'user' => a_hash_including('id' => service_account.to_global_id.to_s)
        )
      end
    end

    context 'when switching from catalog item to config_path' do
      let_it_be_with_reload(:catalog_trigger) do
        create(:ai_flow_trigger,
          :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: item_consumer1
        )
      end

      let(:params) do
        {
          id: catalog_trigger.to_global_id,
          user_id: service_account.to_global_id,
          description: description,
          event_types: event_types,
          config_path: 'new/config/path.yml',
          ai_catalog_item_consumer_id: nil
        }
      end

      it 'updates to use config_path' do
        execute

        catalog_trigger.reload
        expect(catalog_trigger).to have_attributes(
          description: description,
          user_id: service_account.id,
          event_types: event_types,
          config_path: 'new/config/path.yml',
          ai_catalog_item_consumer_id: nil
        )
      end

      it 'returns the updated trigger with config path data' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to match a_hash_including(
          'description' => description,
          'eventTypes' => event_types,
          'configPath' => 'new/config/path.yml',
          'configUrl' => "/#{project.full_path}/-/blob/#{project.default_branch}/new/config/path.yml",
          'aiCatalogItemConsumer' => nil,
          'project' => a_hash_including('id' => project.to_global_id.to_s),
          'user' => a_hash_including('id' => service_account.to_global_id.to_s)
        )
      end
    end

    context 'when updating catalog item' do
      let_it_be_with_reload(:catalog_trigger) do
        create(:ai_flow_trigger,
          :for_catalog_consumer,
          project: project,
          ai_catalog_item_consumer: item_consumer1)
      end

      let(:params) do
        {
          id: catalog_trigger.to_global_id,
          description: description,
          event_types: event_types,
          ai_catalog_item_consumer_id: item_consumer2.to_global_id
        }
      end

      it 'updates to different catalog item' do
        execute

        catalog_trigger.reload
        expect(catalog_trigger).to have_attributes(
          description: description,
          user_id: nil,
          event_types: event_types,
          ai_catalog_item_consumer_id: item_consumer2.id
        )
      end

      context 'when the user_id param is explicitly set to nil' do
        let(:params) { super().merge(user_id: nil) }

        it 'updates the new trigger without causing any exception' do
          execute

          expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to match a_hash_including(
            'description' => description,
            'user' => a_hash_including('id' => item_consumer2.parent_item_consumer.service_account.to_global_id.to_s)
          )
        end
      end

      it 'returns the updated trigger with new catalog item data' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger)).to match a_hash_including(
          'description' => description,
          'eventTypes' => event_types,
          'aiCatalogItemConsumer' => a_hash_including('id' => item_consumer2.to_global_id.to_s)
        )
      end
    end

    context 'with invalid catalog item parameters' do
      let(:params) do
        {
          id: trigger.to_global_id,
          user_id: service_account.to_global_id,
          description: description,
          event_types: event_types,
          config_path: nil,
          ai_catalog_item_consumer_id: nil
        }
      end

      it 'returns an error' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :errors).first).to include(
          'Exactly one of config_path, ai_catalog_item_consumer must be present'
        )
      end
    end
  end

  context 'when adding the scheduled event type to an unsupported target' do
    let_it_be(:external_agent_parent) do
      create(:ai_catalog_item_consumer, :parent_item_consumer,
        group: project.root_ancestor, service_account: service_account,
        item: create(:ai_catalog_third_party_flow))
    end

    let_it_be(:external_agent_consumer) do
      create(:ai_catalog_item_consumer, :child_item_consumer,
        project: project, parent_item_consumer: external_agent_parent, item: external_agent_parent.item)
    end

    let(:unsupported_target_message) do
      'Scheduled triggers are not supported for external agents or configuration file flows'
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog).and_return(true)
      stub_validate_config_service
    end

    shared_examples 'a rejected scheduled event type' do
      it 'returns the error and leaves the event types unchanged', :aggregate_failures do
        expect { execute }.not_to change { target.reload.event_types }

        expect(graphql_data_at(:ai_flow_trigger_update, :errors))
          .to contain_exactly(a_string_including(unsupported_target_message))
      end
    end

    context 'with an external agent' do
      let_it_be_with_reload(:target) do
        create(:ai_flow_trigger, :for_catalog_consumer,
          project: project, ai_catalog_item_consumer: external_agent_consumer)
      end

      let(:params) do
        { id: target.to_global_id, event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]] }
      end

      it_behaves_like 'a rejected scheduled event type'
    end

    context 'with a configuration file flow' do
      let_it_be_with_reload(:target) { create(:ai_flow_trigger, project: project, user: service_account) }

      let(:params) do
        { id: target.to_global_id, event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]] }
      end

      it_behaves_like 'a rejected scheduled event type'
    end
  end

  context 'with a group trigger' do
    let_it_be(:group) { create(:group) }
    let_it_be(:group_maintainer) { create(:user, maintainer_of: group) }
    let_it_be_with_reload(:trigger) { create(:ai_flow_trigger, :for_inheritance_consumer, group: group) }

    let(:current_user) { group_maintainer }
    let(:params) do
      {
        id: trigger.to_global_id,
        description: description,
        ai_catalog_item_consumer_id: trigger.ai_catalog_item_consumer.to_global_id
      }
    end

    context 'when user is a group developer' do
      let(:current_user) { create(:user, developer_of: group) }

      it_behaves_like 'an authorization failure'
    end

    it 'updates the flow trigger and audits it on the group' do
      execute

      expect(graphql_data_at(:ai_flow_trigger_update, :errors)).to be_empty
      expect(graphql_data_at(:ai_flow_trigger_update, :ai_flow_trigger, :group, :id)).to eq(group.to_global_id.to_s)
      expect(trigger.reload.description).to eq('New')
      expect(AuditEventReader.last).to have_attributes(entity_type: 'Group', entity_id: group.id)
    end

    context 'when adding the scheduled event type' do
      let(:params) { { id: trigger.to_global_id, event_types: [Ai::FlowTrigger::EVENT_TYPES[:scheduled]] } }

      it 'returns the service error' do
        execute

        expect(graphql_data_at(:ai_flow_trigger_update, :errors)).to contain_exactly(
          'Scheduled triggers are not supported for group configurations'
        )
      end
    end

    context 'with granular token permissions' do
      it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ai_flow_trigger do
        let(:user) { current_user }
        let(:boundary_object) { group }
        let(:authz_mutation) { graphql_mutation(:ai_flow_trigger_update, params, 'errors') }
        let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
      end
    end
  end
end
