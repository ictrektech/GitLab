# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :in_group) }

  def create_project_trigger(reference: 'developer/v1', **attributes)
    item = create(:ai_catalog_item, :flow, :public, foundational_flow_reference: reference)

    create(:ai_flow_trigger, :for_catalog_consumer,
      project: project,
      ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item),
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]],
      **attributes)
  end

  def create_inherited_trigger
    item = create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')

    create(:ai_flow_trigger, :for_inheritance_consumer,
      group: project.root_ancestor,
      ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :inheritance, group: project.root_ancestor,
        item: item),
      event_types: [Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
  end

  def action_filter(action)
    rule = { 'field' => 'action', 'operator' => 'eq', 'value' => action }

    { 'merge_request' => { 'match' => 'all', 'rules' => [rule] } }
  end

  describe '.applies_to?' do
    it 'is true for a Duo Developer flow trigger' do
      flow_trigger = instance_double(Ai::FlowTrigger, foundational_flow: Ai::Catalog::FoundationalFlow.developer_v1)

      expect(described_class.applies_to?(flow_trigger)).to be(true)
    end

    it 'is false for a flow trigger of another foundational flow' do
      flow_trigger = instance_double(Ai::FlowTrigger, foundational_flow: Ai::Catalog::FoundationalFlow.code_review_v1)

      expect(described_class.applies_to?(flow_trigger)).to be(false)
    end

    it 'is false for a flow trigger without a foundational flow' do
      expect(described_class.applies_to?(build_stubbed(:ai_flow_trigger))).to be(false)
    end
  end

  describe '.flow_trigger_for' do
    subject(:flow_trigger) { described_class.flow_trigger_for(project) }

    it 'returns the first active Duo Developer flow trigger that a request for changes starts' do
      create_project_trigger(active: false)
      create_project_trigger(reference: nil)
      create_project_trigger(filter: action_filter('approved'))
      first_trigger = create_project_trigger(filter: action_filter('requested_changes'))
      create_project_trigger

      expect(flow_trigger).to eq(first_trigger)
    end

    it 'returns a flow trigger that the top-level group passes on' do
      inherited_trigger = create_inherited_trigger

      expect(flow_trigger).to eq(inherited_trigger)
    end

    it 'is nil when no flow trigger starts a fix run' do
      create_project_trigger(filter: action_filter('approved'))

      expect(flow_trigger).to be_nil
    end
  end

  describe '.add_inherited_service_account' do
    subject(:add_service_account) { described_class.add_inherited_service_account(flow_trigger, project) }

    context 'with a flow trigger of the project' do
      let(:flow_trigger) { create_project_trigger }

      it 'does not add the service account to the project' do
        expect(Ai::Catalog::AddServiceAccountToProjectService).not_to receive(:new)

        add_service_account
      end
    end

    context 'with a flow trigger that the top-level group passes on' do
      let(:flow_trigger) { create_inherited_trigger }

      it 'adds the service account to the project' do
        add_service_account

        expect(project.member(flow_trigger.service_account)).to be_present
      end

      context 'when the service account does not join the project' do
        before do
          allow_next_instance_of(Ai::Catalog::AddServiceAccountToProjectService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Lock not obtained'))
          end
        end

        it 'logs the error' do
          expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(
            message: 'Fix loop could not add the service account to the project.',
            flow_trigger_id: flow_trigger.id,
            project_id: project.id,
            error_message: 'Lock not obtained'
          ))

          add_service_account
        end
      end

      context 'when the flow trigger has no service account' do
        before do
          Ai::Catalog::ItemConsumer.id_in(flow_trigger.ai_catalog_item_consumer_id).update_all(service_account_id: nil)
          flow_trigger.reload
        end

        it 'does not add a service account to the project' do
          expect(Ai::Catalog::AddServiceAccountToProjectService).not_to receive(:new)

          add_service_account
        end
      end
    end
  end
end
