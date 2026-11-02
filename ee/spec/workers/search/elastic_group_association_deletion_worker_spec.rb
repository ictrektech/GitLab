# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::ElasticGroupAssociationDeletionWorker, :elastic_helpers, feature_category: :global_search do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(group.id, parent_group.id) }

    let_it_be(:parent_group) { create(:group) }
    let_it_be(:group) { create(:group, parent: parent_group) }
    let_it_be(:sub_group) { create(:group, parent: group) }
    let(:helper) { Search::Elastic::Helper.default }
    let(:client) { helper.client }
    let(:work_item_index) { ::Search::Elastic::Types::WorkItem.index_name }

    it 'is a pause_control worker' do
      expect(described_class.get_pause_control).to eq(:advanced_search)
    end

    context 'when Elasticsearch is enabled', :elastic_delete_by_query do
      let(:group_work_item) { create(:work_item, namespace: group) }
      let(:sub_group_work_item) { create(:work_item, namespace: sub_group) }

      before do
        stub_ee_application_setting(elasticsearch_indexing: true)

        group_work_item
        sub_group_work_item
        ensure_elasticsearch_index!
      end

      context 'when work_item index is available' do
        context 'when we pass include_descendants' do
          it 'deletes work items belonging to the group and its descendants' do
            # items are present already
            expect(items_in_index(work_item_index).count).to eq(2)
            expect(items_in_index(work_item_index)).to include(group_work_item.id)
            expect(items_in_index(work_item_index)).to include(sub_group_work_item.id)

            described_class.new.perform(group.id, parent_group.id, { include_descendants: true })
            helper.refresh_index(index_name: work_item_index)

            # items are deleted
            expect(items_in_index(work_item_index).count).to eq(0)
          end
        end

        context 'when we do not pass include_descendants' do
          it 'deletes work_items belonging to the group' do
            # items are present already
            expect(items_in_index(work_item_index).count).to eq(2)
            expect(items_in_index(work_item_index)).to include(group_work_item.id)
            expect(items_in_index(work_item_index)).to include(sub_group_work_item.id)

            described_class.new.perform(group.id, parent_group.id)
            helper.refresh_index(index_name: work_item_index)

            # sub group work item is present
            expect(items_in_index(work_item_index).count).to eq(1)
            expect(items_in_index(work_item_index)).to include(sub_group_work_item.id)
          end
        end

        it 'keeps work items already reindexed under a new root ancestor on the same shard' do
          reindexed_id = non_existing_record_id
          es_client.index(
            index: work_item_index,
            id: "work_item_#{reindexed_id}_#{group.id}",
            routing: "group_#{parent_group.id}",
            refresh: true,
            body: {
              type: 'work_item', id: reindexed_id, namespace_id: group.id,
              traversal_ids: "#{non_existing_record_id}-#{group.id}-"
            }
          )

          perform
          helper.refresh_index(index_name: work_item_index)

          expect(items_in_index(work_item_index)).to contain_exactly(reindexed_id, sub_group_work_item.id)
        end
      end

      context 'with milestones' do
        let(:main_index) { Elastic::Latest::Config.index_name }
        let(:group_milestone) { create(:milestone, group: group) }
        let(:sub_group_milestone) { create(:milestone, group: sub_group) }
        let(:project_milestone) { create(:milestone, project: create(:project, group: group)) }

        before do
          group_milestone
          sub_group_milestone
          project_milestone
          ensure_elasticsearch_index!
        end

        def milestone_ids_in_index
          es_client.search(
            index: main_index,
            body: { query: { term: { type: 'milestone' } } }
          ).dig('hits', 'hits').map { |hit| hit['_source']['id'] }
        end

        it 'deletes only the group milestones' do
          expect(milestone_ids_in_index).to contain_exactly(
            group_milestone.id, sub_group_milestone.id, project_milestone.id
          )

          perform
          helper.refresh_index(index_name: main_index)

          expect(milestone_ids_in_index).to contain_exactly(sub_group_milestone.id, project_milestone.id)
        end

        it 'deletes the milestones of descendant groups when we pass include_descendants' do
          described_class.new.perform(group.id, parent_group.id, { include_descendants: true })
          helper.refresh_index(index_name: main_index)

          expect(milestone_ids_in_index).to contain_exactly(project_milestone.id)
        end

        it 'keeps group milestones already reindexed under a new root ancestor on the same shard' do
          reindexed_id = non_existing_record_id
          es_client.index(
            index: main_index,
            id: "milestone_#{reindexed_id}",
            routing: "n_#{parent_group.id}",
            refresh: true,
            body: {
              type: 'milestone', id: reindexed_id, namespace_id: group.id,
              traversal_ids: "#{non_existing_record_id}-#{group.id}-"
            }
          )

          perform
          helper.refresh_index(index_name: main_index)

          expect(milestone_ids_in_index).to contain_exactly(
            reindexed_id, sub_group_milestone.id, project_milestone.id
          )
        end
      end
    end
  end
end
