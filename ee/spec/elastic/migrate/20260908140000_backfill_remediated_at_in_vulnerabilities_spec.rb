# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260908140000_backfill_remediated_at_in_vulnerabilities.rb')

RSpec.describe BackfillRemediatedAtInVulnerabilities, feature_category: :vulnerability_management do
  let(:version) { 20260908140000 }

  describe 'migration', :elastic_delete_by_query, :sidekiq_inline do
    include_examples 'migration reindex based on schema_version' do
      let(:expected_throttle_delay) { 15.seconds }
      let(:expected_batch_size) { 10_000 }

      let(:objects) do
        create_list(:vulnerability_read, 3).each do |read|
          allow(read).to receive(:dual_write_to_es?).and_return(false)
        end
      end
    end
  end

  describe 'remediated_at backfill', :elastic_delete_by_query, :sidekiq_inline do
    let(:migration) { described_class.new(version) }

    before do
      stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
      set_elasticsearch_migration_to(version, including: false)
      allow(vulnerability_read).to receive(:dual_write_to_es?).and_return(false)

      migration.send(:bookkeeping_service).track!(vulnerability_read)
      ensure_elasticsearch_index!

      # Rewind the document to the shape it had before remediated_at was indexed
      es_client.update_by_query(
        index: migration.index_name,
        wait_for_completion: true,
        refresh: true,
        body: {
          script: {
            source: "ctx._source.schema_version=#{described_class::NEW_SCHEMA_VERSION.pred}; " \
              "ctx._source.remove('remediated_at')"
          },
          query: { term: { vulnerability_id: vulnerability_read.vulnerability_id } }
        }
      )
      migration.set_migration_state(documents_remaining: nil, scroll_id: nil, last_processed_id: nil)
    end

    shared_examples 'a backfilled remediated_at' do
      it 'populates remediated_at on the reindexed document', :aggregate_failures do
        expect(indexed_document).not_to have_key('remediated_at')

        migration.migrate
        ensure_elasticsearch_index!

        expect(indexed_document['schema_version']).to eq(described_class::NEW_SCHEMA_VERSION)
        expect(Time.zone.parse(indexed_document['remediated_at'])).to be_within(1.second).of(expected_remediated_at)
      end
    end

    context 'when the vulnerability was resolved' do
      let(:resolved_at) { 3.days.ago }
      let(:expected_remediated_at) { resolved_at }
      let(:vulnerability_read) { create(:vulnerability, :with_read, resolved_at: resolved_at).vulnerability_read }

      it_behaves_like 'a backfilled remediated_at'
    end

    context 'when the vulnerability stopped being detected' do
      let(:undetected_since) { 2.days.ago }
      let(:expected_remediated_at) { undetected_since }
      let(:vulnerability_read) do
        vulnerability = create(:vulnerability, :with_read)
        finding = create(:vulnerabilities_finding, vulnerability: vulnerability)
        create(:vulnerability_detection_transition, :not_detected, finding: finding, created_at: undetected_since)

        vulnerability.vulnerability_read
      end

      it_behaves_like 'a backfilled remediated_at'
    end

    def indexed_document
      items_in_index(migration.index_name, source: true)
        .find { |doc| doc['vulnerability_id'] == vulnerability_read.vulnerability_id }
    end
  end
end
