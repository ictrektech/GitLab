# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Milestone, :elastic, feature_category: :global_search do
  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  it_behaves_like 'limited indexing is enabled' do
    let_it_be(:object) { create :milestone, project: project }
  end

  describe 'searching', :sidekiq_inline do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, developers: user) }
    let_it_be(:milestone_1) { create(:milestone, title: 'bla-bla term1', project: project) }
    let_it_be(:milestone_2) { create(:milestone, title: 'bla-bla term2', project: project) }
    let_it_be(:milestone_3) { create(:milestone, project: project) }
    # The milestone you have no access to except as an administrator
    let_it_be(:milestone_4) { create(:milestone, title: 'bla-bla term3') }

    before do
      Elastic::ProcessInitialBookkeepingService.track!(milestone_1, milestone_2, milestone_3, milestone_4)
      ensure_elasticsearch_index!
    end

    it 'searches milestones', :enable_admin_mode do
      options = { search_level: 'global', project_ids: [project.id], current_user: user }

      expect(described_class.elastic_search('(term1 | term2 | term3) +bla-bla', options: options).total_count).to eq(2)

      options = { current_user: create(:admin), search_level: 'global', project_ids: :any }
      expect(described_class.elastic_search('bla-bla', options: options).total_count).to eq(3)
    end

    context 'with a group milestone' do
      let_it_be(:group) { create(:group, developers: user) }
      let(:group_milestone) { create(:milestone, title: 'bla-bla term4', group: group) }

      before do
        group_milestone
        ensure_elasticsearch_index!
      end

      it 'indexes the group milestone but does not return it', :enable_admin_mode do
        hits = es_client.search(
          index: Elastic::Latest::Config.index_name,
          body: { query: { bool: { filter: [{ term: { type: 'milestone' } }, { term: { id: group_milestone.id } }] } } }
        ).dig('hits', 'hits')
        expect(hits.pluck('_routing')).to eq(["n_#{group.id}"])

        [
          { search_level: 'global', project_ids: [project.id], current_user: user },
          { search_level: 'global', project_ids: :any, current_user: create(:admin) }
        ].each do |options|
          expect(described_class.elastic_search('term4', options: options).total_count).to eq(0)
        end
      end
    end
  end

  describe 'group visibility change', :sidekiq_inline do
    let(:group) { create(:group, :public) }
    let(:milestone) { create(:milestone, group: group) }

    def indexed_visibility_level
      es_client.search(
        index: Elastic::Latest::Config.index_name,
        body: { query: { bool: { filter: [{ term: { type: 'milestone' } }, { term: { id: milestone.id } }] } } }
      ).dig('hits', 'hits', 0, '_source', 'visibility_level')
    end

    it 'updates the visibility_level of the indexed group milestone' do
      allow(ElasticWikiIndexerWorker).to receive(:perform_async)
      milestone
      ensure_elasticsearch_index!
      expect(indexed_visibility_level).to eq(Gitlab::VisibilityLevel::PUBLIC)

      group.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
      ensure_elasticsearch_index!

      expect(indexed_visibility_level).to eq(Gitlab::VisibilityLevel::PRIVATE)
    end
  end

  describe '#es_parent' do
    let_it_be(:root_group) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root_group) }
    let_it_be(:project) { create(:project, group: subgroup) }

    it 'routes a project milestone by its project' do
      milestone = build_stubbed(:milestone, project: project)

      expect(milestone.es_parent).to eq("project_#{project.id}")
    end

    it 'routes a group milestone by its root ancestor' do
      milestone = build_stubbed(:milestone, group: subgroup)

      expect(milestone.es_parent).to eq("n_#{root_group.id}")
    end
  end

  describe 'as_indexed_json' do
    context 'for project milestone' do
      let_it_be(:milestone) { create(:milestone, :on_project) }

      let(:expected_hash) do
        milestone.attributes.extract!(
          'id',
          'iid',
          'title',
          'description',
          'project_id',
          'created_at',
          'updated_at'
        ).merge({
          'type' => milestone.es_type,
          'issues_access_level' => milestone.project.issues_access_level,
          'merge_requests_access_level' => milestone.project.merge_requests_access_level,
          'visibility_level' => milestone.project.visibility_level,
          'archived' => milestone.project.archived,
          'schema_version' => Elastic::Latest::MilestoneInstanceProxy::SCHEMA_VERSION,
          'traversal_ids' => milestone.project.elastic_namespace_ancestry,
          'organization_id' => milestone.project.organization_id,
          'organization_traversal_ids' =>
            "#{milestone.project.organization_id}/#{milestone.project.elastic_namespace_ancestry}"
        })
      end

      it 'returns json with all needed elements' do
        expect(milestone.__elasticsearch__.as_indexed_json).to eq(expected_hash)
      end
    end

    context 'for group milestone' do
      let_it_be(:milestone) { create(:milestone, :on_group) }

      let(:expected_hash) do
        milestone.attributes.extract!(
          'id',
          'iid',
          'title',
          'description',
          'project_id',
          'created_at',
          'updated_at'
        ).merge({
          'type' => milestone.es_type,
          'namespace_id' => milestone.group.id,
          'visibility_level' => milestone.group.visibility_level,
          'archived' => false,
          'schema_version' => Elastic::Latest::MilestoneInstanceProxy::SCHEMA_VERSION,
          'traversal_ids' => milestone.group.elastic_namespace_ancestry,
          'organization_id' => milestone.group.organization_id,
          'organization_traversal_ids' =>
            "#{milestone.group.organization_id}/#{milestone.group.elastic_namespace_ancestry}"
        })
      end

      it 'returns json with all needed elements' do
        expect(milestone.__elasticsearch__.as_indexed_json).to eq(expected_hash)
      end
    end

    context 'for group milestone under an archived group' do
      let_it_be(:archived_group) { create(:group, :archived) }
      let_it_be(:milestone) { create(:milestone, group: create(:group, parent: archived_group)) }

      it 'marks the document as archived' do
        expect(milestone.__elasticsearch__.as_indexed_json['archived']).to be(true)
      end
    end

    context 'for group milestones in subgroups' do
      let_it_be(:root_group) { create(:group) }

      before_all do
        create(:milestone, group: create(:group, parent: root_group))
      end

      def build_documents
        described_class.preload_for_indexing.find_each { |milestone| milestone.__elasticsearch__.as_indexed_json }
      end

      it 'does not issue a query per milestone' do
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { build_documents }

        create(:milestone, group: create(:group, parent: root_group))

        expect { build_documents }.to issue_same_number_of_queries_as(control)
      end
    end
  end

  it_behaves_like 'no results when the user cannot read cross project' do
    let(:record1) { create(:milestone, project: project, title: 'test-milestone') }
    let(:record2) { create(:milestone, project: project2, title: 'test-milestone') }
  end
end
