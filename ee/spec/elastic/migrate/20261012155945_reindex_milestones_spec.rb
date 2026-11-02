# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261012155945_reindex_milestones.rb')

RSpec.describe ReindexMilestones, :elastic, feature_category: :global_search do
  let(:version) { 20261012155945 }

  describe 'skip_migration?' do
    subject(:skip_migration?) { described_class.new(version).skip_migration? }

    context 'when the instance is GitLab.com' do
      before do
        stub_saas_features(advanced_search: true)
      end

      it { is_expected.to be true }
    end

    context 'when the instance is not GitLab.com' do
      before do
        stub_saas_features(advanced_search: false)
      end

      it { is_expected.to be false }
    end
  end

  it_behaves_like 'migration reindexes all data' do
    let(:objects) do
      root_group = create(:group)

      [
        create(:milestone, project: create(:project)),
        create(:milestone, group: root_group),
        create(:milestone, group: create(:group, parent: root_group))
      ]
    end

    let(:expected_throttle_delay) { 1.minute }
    let(:expected_batch_size) { 50_000 }
  end

  context 'with project and group milestones' do
    let(:migration) { described_class.new(version) }

    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:project) { create(:project, group: subgroup) }
    let_it_be(:group_milestones) { [create(:milestone, group: root_group), create(:milestone, group: subgroup)] }
    let_it_be(:project_milestone) { create(:milestone, project: project) }

    before do
      stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
      set_elasticsearch_migration_to(version, including: false)
      migration.set_migration_state(current_id: 0)
    end

    it 'indexes group milestones routed by their root ancestor' do
      migration.migrate
      ensure_elasticsearch_index!

      hits = es_client.search(
        index: Elastic::Latest::Config.index_name,
        body: {
          query: { bool: { filter: [{ term: { type: 'milestone' } }, { terms: { id: group_milestones.map(&:id) } }] } }
        }
      ).dig('hits', 'hits')

      expect(hits.pluck('_routing')).to contain_exactly("n_#{root_group.id}", "n_#{root_group.id}")
    end

    it 'does not trigger N+1 queries', :use_sql_query_cache do
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) { migration.migrate }

      create(:milestone, group: create(:group, parent: create(:group)))
      create(:milestone, project: create(:project))
      migration.set_migration_state(current_id: 0)

      expect { migration.migrate }.to issue_same_number_of_queries_as(control)
    end

    it 'tracks only milestones in indexed namespaces when limited indexing is on' do
      stub_ee_application_setting(elasticsearch_limit_indexing: true)
      create(:elasticsearch_indexed_namespace, namespace: root_group)
      create(:milestone, group: create(:group))
      create(:milestone, project: create(:project))

      expect(::Elastic::ProcessInitialBookkeepingService).to receive(:track!)
        .once.with(*group_milestones, project_milestone).and_call_original

      migration.migrate
    end
  end
end
