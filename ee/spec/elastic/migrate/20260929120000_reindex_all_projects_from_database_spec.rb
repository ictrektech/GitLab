# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260929120000_reindex_all_projects_from_database.rb')

RSpec.describe ReindexAllProjectsFromDatabase, :elastic, feature_category: :global_search do
  let(:version) { 20260929120000 }

  describe 'skip_migration?' do
    subject(:skip_migration?) { described_class.new(version).skip_migration? }

    context 'when the instance is GitLab.com' do
      before do
        stub_saas_features(advanced_search: true)
      end

      it { is_expected.to be false }
    end

    context 'when the instance is not GitLab.com' do
      before do
        stub_saas_features(advanced_search: false)
      end

      it { is_expected.to be true }
    end
  end

  include_examples 'migration reindexes all data' do
    let(:objects) { create_list(:project, 3) }
    let(:factory_to_create_objects) { :project }
    let(:expected_throttle_delay) { 1.minute }
    let(:expected_batch_size) { 50_000 }
  end
end
