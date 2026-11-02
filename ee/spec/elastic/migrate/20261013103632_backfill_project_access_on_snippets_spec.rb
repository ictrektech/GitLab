# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261013103632_backfill_project_access_on_snippets.rb')

RSpec.describe BackfillProjectAccessOnSnippets, feature_category: :global_search do
  let(:version) { 20261013103632 }

  it 'retries on failure so a persistently failing run halts instead of blocking later migrations' do
    expect(described_class.new(version)).to be_retry_on_failure
  end

  describe 'migration', :elastic_delete_by_query, :sidekiq_inline do
    include_examples 'migration reindex based on schema_version' do
      let(:expected_throttle_delay) { 1.minute }
      let(:expected_batch_size) { 10_000 }

      let(:objects) { [create(:project_snippet), create(:project_snippet), create(:personal_snippet)] }
    end

    describe 'project access fields' do
      let_it_be(:project) { create(:project, :internal, :snippets_private) }
      let_it_be(:project_snippet) { create(:project_snippet, project: project) }

      let(:migration) { described_class.new(version) }
      let(:client) { Gitlab::Search::Client.new }
      let(:index_name) { migration.index_name }
      # The baseline version, which predates the project access fields.
      let(:previous_schema_version) { Elastic::Latest::SnippetInstanceProxy::SCHEMA_VERSIONS.keys.min }

      before do
        stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
        set_elasticsearch_migration_to(version, including: false)

        ::Elastic::ProcessInitialBookkeepingService.track!(project_snippet)
        ensure_elasticsearch_index!

        # A document indexed before the mapping migration: old schema version and no project fields.
        client.update_by_query(
          index: index_name,
          wait_for_completion: true,
          refresh: true,
          body: {
            script: {
              lang: 'painless',
              source: "ctx._source.schema_version = #{previous_schema_version}; " \
                "ctx._source.remove('project_visibility_level'); ctx._source.remove('snippets_access_level')"
            },
            query: { bool: { filter: [{ term: { type: 'snippet' } }, { term: { id: project_snippet.id } }] } }
          }
        )
      end

      it 'writes the project visibility and snippets access level back onto the document' do
        migration.migrate
        ensure_elasticsearch_index!

        source = client.get(index: index_name, id: "snippet_#{project_snippet.id}")['_source']

        expect(source).to include(
          'project_visibility_level' => Gitlab::VisibilityLevel::INTERNAL,
          'snippets_access_level' => ProjectFeature::PRIVATE,
          'schema_version' => described_class::NEW_SCHEMA_VERSION
        )
        expect(migration).to be_completed
      end
    end
  end
end
