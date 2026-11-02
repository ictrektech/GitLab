# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumerAuthorizationSubject, feature_category: :ai_catalog_curation do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: create(:group, parent: group)) }
  let_it_be(:other_project) { create(:project) }

  let(:item_consumer) { build_stubbed(:ai_catalog_item_consumer, :inheritance, group: group) }

  describe '#id' do
    it 'combines the item consumer and project ids' do
      expect(described_class.new(item_consumer, project).id).to eq("#{item_consumer.id}-#{project.id}")
    end
  end

  describe '#inherited_by_project?' do
    it 'returns true when the project is in the group hierarchy of the item consumer' do
      expect(described_class.new(item_consumer, project).inherited_by_project?).to be(true)
    end

    it 'returns false when the project is outside the group hierarchy of the item consumer' do
      expect(described_class.new(item_consumer, other_project).inherited_by_project?).to be(false)
    end

    context 'when the item consumer is a direct record' do
      let(:item_consumer) { build_stubbed(:ai_catalog_item_consumer, :parent_item_consumer, group: group) }

      it 'returns false' do
        expect(described_class.new(item_consumer, project).inherited_by_project?).to be(false)
      end
    end
  end
end
