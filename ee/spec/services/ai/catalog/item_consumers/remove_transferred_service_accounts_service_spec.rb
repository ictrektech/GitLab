# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumers::RemoveTransferredServiceAccountsService,
  feature_category: :ai_catalog_curation do
  let_it_be(:current_user) { create(:user) }
  let_it_be(:old_group) { create(:group) }
  let_it_be(:new_group) { create(:group) }
  let_it_be(:project) { create(:project, group: old_group) }
  let_it_be(:other_project) { create(:project, group: old_group) }
  let_it_be(:mention) { ::Ai::FlowTrigger::EVENT_TYPES[:mention] }

  let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: old_group) }

  let_it_be(:direct_project_consumer) do
    create(:ai_catalog_item_consumer, :child_item_consumer, :with_triggers, project: project, event_types: [mention])
  end

  let_it_be(:foundational_project_consumer) do
    create(:ai_catalog_item_consumer, :child_item_consumer, :with_triggers,
      project: project, event_types: [mention],
      item: create(:ai_catalog_flow, :with_foundational_flow_reference, foundational_flow_reference: 'developer/v1'))
  end

  let_it_be(:group_only_consumer) { create(:ai_catalog_item_consumer, :parent_item_consumer, group: old_group) }

  let_it_be(:service_accounts) do
    {
      inheritance: inheritance_consumer.service_account,
      direct: direct_project_consumer.parent_item_consumer.service_account,
      group_only: group_only_consumer.service_account,
      foundational: foundational_project_consumer.parent_item_consumer.service_account
    }
  end

  subject(:execute) do
    described_class.new(project: project, old_root_namespace_id: old_group.id, current_user: current_user).execute
  end

  before_all do
    [project, other_project].each { |p| p.team.add_members(service_accounts.values, :developer) }
  end

  before do
    Project.id_in(project.id).update_all(namespace_id: new_group.id)
  end

  describe '#execute' do
    it 'removes the old group inheritance and direct service accounts from the project', :aggregate_failures do
      expect(execute).to be_success

      expect(project.member(service_accounts[:inheritance])).to be_nil
      expect(project.member(service_accounts[:direct])).to be_nil
    end

    it 'removes old group direct service accounts that the project has no configuration for' do
      expect { execute }.to change { project.member(service_accounts[:group_only]) }.from(be_present).to(nil)
    end

    it 'deactivates the triggers of the old group direct configurations' do
      expect { execute }.to change { direct_project_consumer.flow_trigger.reload.active }.from(true).to(false)
    end

    it 'keeps the direct project configuration' do
      execute

      expect(Ai::Catalog::ItemConsumer.exists?(direct_project_consumer.id)).to be(true)
    end

    it 'leaves foundational flows alone', :aggregate_failures do
      execute

      expect(project.member(service_accounts[:foundational])).to be_present
      expect(foundational_project_consumer.flow_trigger.reload.active).to be(true)
    end

    it 'does not touch other projects in the old group' do
      expect { execute }.not_to change { other_project.members.count }
    end
  end
end
