# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260911120000_add_title_keyword_to_work_items.rb')

RSpec.describe AddTitleKeywordToWorkItems, :elastic, feature_category: :global_search do
  let(:version) { 20260911120000 }

  include_examples 'migration adds mapping'

  # The shared examples read the real index, which is built from
  # Search::Elastic::Types::WorkItem.mappings, so they catch new_mappings drifting from
  # base_mappings. They do not cover the sub-field itself: MigrationUpdateMappingsHelper#completed?
  # compares only top-level mapping keys, and `title` already exists, so the shared implementation
  # would report completed before the keyword sub-field was ever added.
  describe 'the title.keyword sub-field specifically' do
    let(:migration) { described_class.new(version) }
    let(:helper) { Search::Elastic::Helper.new }
    let(:mapping_without_keyword) { { 'title' => { 'type' => 'text' } } }

    before do
      allow(migration).to receive(:helper).and_return(helper)
      allow(helper).to receive(:get_mapping).and_return(mapping_without_keyword)
    end

    it 'is not completed when title exists without the sub-field' do
      expect(migration).not_to be_completed
    end

    it 'adds the sub-field to the existing title field' do
      expect(helper).to receive(:update_mapping) do |index_name:, mappings:|
        expect(index_name).to eq(Search::Elastic::Types::WorkItem.index_name)
        expect(mappings.dig(:properties, :title, :fields, :keyword)).to eq(
          type: 'keyword', normalizer: 'lower_case_normalizer', ignore_above: 1024
        )
      end

      migration.migrate
    end
  end
end
