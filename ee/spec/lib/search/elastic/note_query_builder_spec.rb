# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::NoteQueryBuilder, :elastic_helpers, feature_category: :global_search do
  let_it_be(:user) { create(:user) }

  let(:base_options) do
    {
      current_user: user,
      project_ids: [],
      group_ids: [],
      search_level: 'global',
      public_and_internal_projects: true
    }
  end

  let(:query) { 'foo' }
  let(:options) { base_options }

  subject(:build) { described_class.build(query: query, options: options) }

  before do
    allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?).and_call_original
    allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
      .with(::Elastic::Latest::NoteInstanceProxy::HIDDEN_BACKFILL_MIGRATION).and_return(true)
  end

  it 'contains all expected filters' do
    assert_names_in_query(build, with: %w[
      note:multi_match:and:search_terms
      note:multi_match_phrase:search_terms
      filters:permissions:global:visibility_level:public_and_internal
      filters:confidentiality:notes:not_confidential
      filters:not_hidden
      filters:non_archived
    ])
  end

  context 'when advanced query syntax is used' do
    let(:query) { 'foo -default' }

    it 'uses simple_query_string in query' do
      assert_names_in_query(build, with: %w[note:match:search_terms],
        without: %w[note:multi_match:and:search_terms note:multi_match_phrase:search_terms])
    end
  end

  context 'when the query is blank' do
    let(:query) { ' ' }

    it 'matches all notes and still applies the filters' do
      expect(build.dig(:query, :bool, :must)).to eq(match_all: {})
      assert_names_in_query(build, with: %w[
        filters:permissions:global:visibility_level:public_and_internal
        filters:confidentiality:notes:not_confidential
        filters:non_archived
      ])
    end
  end

  describe 'fields' do
    it 'defaults to note' do
      assert_fields_in_query(build, with: %w[note])
    end
  end

  describe 'features' do
    it 'authorizes every noteable feature by default' do
      assert_names_in_query(build, with: %w[
        filters:permissions:global:issues_access_level:enabled
        filters:permissions:global:merge_requests_access_level:enabled
        filters:permissions:global:repository_access_level:enabled
        filters:permissions:global:snippets_access_level:enabled
      ])
    end

    context 'when noteable_type is set' do
      let(:options) { base_options.merge(noteable_type: 'Issue') }

      it 'authorizes only that noteable feature and filters by noteable type' do
        assert_names_in_query(build,
          with: %w[filters:permissions:global:issues_access_level:enabled filters:related:issue],
          without: %w[
            filters:permissions:global:merge_requests_access_level:enabled
            filters:permissions:global:repository_access_level:enabled
            filters:permissions:global:snippets_access_level:enabled
          ])
      end
    end
  end

  describe 'confidentiality' do
    context 'when user can read all resources' do
      before do
        allow(user).to receive(:can_read_all_resources?).and_return(true)
      end

      it 'does not apply confidentiality filters' do
        assert_names_in_query(build, without: %w[filters:confidentiality:notes:not_confidential])
      end
    end
  end

  describe 'hidden' do
    it_behaves_like 'a query filtered by hidden'

    context 'when the hidden backfill migration has not finished' do
      before do
        allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
          .with(::Elastic::Latest::NoteInstanceProxy::HIDDEN_BACKFILL_MIGRATION).and_return(false)
      end

      it 'does not apply hidden filters' do
        assert_names_in_query(build, without: %w[filters:not_hidden])
      end
    end
  end

  describe 'archived' do
    it_behaves_like 'a query filtered by archived'
  end

  describe 'formats' do
    it_behaves_like 'a query formatted for size'
    it_behaves_like 'a query that sets source_fields'

    it 'applies highlight' do
      expect(build).to have_key(:highlight)
    end

    context 'when related_ids_only is set' do
      let(:options) { base_options.merge(noteable_type: 'Issue', related_ids_only: true) }

      it 'returns only noteable_id with the related size and no highlight' do
        expect(build).to include(_source: ['noteable_id'], size: ::Search::Elastic::Filters::DEFAULT_RELATED_SIZE)
        expect(build).not_to have_key(:highlight)
      end
    end
  end
end
