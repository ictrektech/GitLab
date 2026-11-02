# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Preloaders::ItemConsumerPolicyPreloader, feature_category: :ai_catalog_curation do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:item) { create(:ai_catalog_agent, :public, project: create(:project, group: group)) }
  let_it_be(:consumer) { create(:ai_catalog_item_consumer, project: project, item: item) }
  let_it_be(:other_consumer) do
    create(:ai_catalog_item_consumer, project: project,
      item: create(:ai_catalog_agent, :public, project: item.project))
  end

  let_it_be(:group_consumer) do
    create(:ai_catalog_item_consumer, group: group, item: create(:ai_catalog_agent, :public, project: item.project))
  end

  describe '#execute' do
    it 'preloads the item and its project' do
      consumers = Ai::Catalog::ItemConsumer.where(id: consumer.id).to_a

      described_class.new(consumers).execute

      loaded = consumers.first
      expect(loaded.association(:item)).to be_loaded
      expect(loaded.item.association(:project)).to be_loaded
    end

    it 'shares one container record across consumers of the same project' do
      consumers = Ai::Catalog::ItemConsumer.id_in([consumer.id, other_consumer.id]).to_a

      described_class.new(consumers).execute

      expect(consumers.first.project).to be(consumers.second.project)
    end

    it 'assigns a shared, preloaded root ancestor to the container and the item project' do
      consumers = Ai::Catalog::ItemConsumer.where(id: consumer.id).to_a

      described_class.new(consumers).execute

      loaded = consumers.first
      container_root = loaded.project.root_ancestor
      expect(loaded.item.project.root_ancestor).to be(container_root)
      expect(container_root).to eq(group)
      expect(container_root.association(:namespace_settings)).to be_loaded
    end

    it 'assigns a preloaded root ancestor to a group container' do
      consumers = Ai::Catalog::ItemConsumer.where(id: group_consumer.id).to_a

      described_class.new(consumers).execute

      group_root = consumers.first.group.root_ancestor
      expect(group_root).to eq(group)
      expect(group_root.association(:namespace_settings)).to be_loaded
    end

    it 'skips the namespace of an item without a project' do
      no_project_consumer = create(:ai_catalog_item_consumer, project: project,
        item: create(:ai_catalog_agent, :public, project: nil))
      consumers = Ai::Catalog::ItemConsumer.where(id: no_project_consumer.id).to_a

      described_class.new(consumers).execute

      container_root = consumers.first.project.root_ancestor
      expect(container_root).to eq(group)
      expect(container_root.association(:namespace_settings)).to be_loaded
    end

    it 'does not query when the container root ancestor is read afterwards' do
      consumers = Ai::Catalog::ItemConsumer.where(id: consumer.id).to_a

      described_class.new(consumers).execute

      expect { consumers.first.project.root_ancestor.namespace_settings }
        .not_to exceed_query_limit(0)
    end
  end
end
