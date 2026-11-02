# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260911120001_backfill_title_keyword_in_work_items.rb')

RSpec.describe BackfillTitleKeywordInWorkItems, feature_category: :global_search do
  let(:version) { 20260911120001 }

  it 'retries on failure so a persistently failing run halts instead of blocking later migrations' do
    expect(described_class.new(version)).to be_retry_on_failure
  end

  describe 'migration', :elastic_delete_by_query, :sidekiq_inline do
    include_examples 'migration reindex based on schema_version' do
      let(:expected_throttle_delay) { 1.minute }
      let(:expected_batch_size) { 10_000 }

      let(:objects) { create_list(:work_item, 3) }
    end
  end
end
