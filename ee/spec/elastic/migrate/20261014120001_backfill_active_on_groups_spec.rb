# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261014120001_backfill_active_on_groups.rb')

RSpec.describe BackfillActiveOnGroups, :elastic_delete_by_query, :sidekiq_inline,
  feature_category: :global_search do
  include_examples 'migration backfills fields' do
    let(:version) { 20261014120001 }
    let(:expected_throttle_delay) { 1.minute }
    let(:expected_batch_size) { 9000 }
    let(:objects) { create_list(:group, 3) }
    let(:expected_fields) { { active: true } }
  end
end
