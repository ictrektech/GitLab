# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Elastic::Sorts::WorkItem, feature_category: :global_search do
  let(:query_hash) { {} }

  before do
    # The title sort keys are gated on the backfill migration; the table below covers the
    # backfill-finished state. The gate itself is exercised in its own describe block.
    allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
      .with(:backfill_title_keyword_in_work_items).and_return(true)
  end

  describe '#sort_by' do
    using RSpec::Parameterized::TableSyntax

    subject(:sort_by) { described_class.sort_by(query_hash: query_hash, options: options) }

    where(:order_by, :sort, :expected) do
      nil | nil | { sort: {} }
      'created_at' | 'asc' | { sort: { created_at: { order: 'asc' } } }
      'created_at' | 'desc' | { sort: { created_at: { order: 'desc' } } }
      'updated_at' | 'asc' | { sort: { updated_at: { order: 'asc' } } }
      'updated_at' | 'desc' | { sort: { updated_at: { order: 'desc' } } }
      'popularity' | 'asc' | { sort: { upvotes: { order: 'asc' } } }
      'popularity' | 'desc' | { sort: { upvotes: { order: 'desc' } } }
      'milestone_due' | 'asc' | { sort: { milestone_due_date: { order: 'asc' } } }
      'milestone_due' | 'desc' | { sort: { milestone_due_date: { order: 'desc' } } }
      'weight' | 'asc' | { sort: { weight: { order: 'asc' } } }
      'weight' | 'desc' | { sort: { weight: { order: 'desc' } } }
      'health_status' | 'asc' | { sort: { health_status: { order: 'asc' } } }
      'health_status' | 'desc' | { sort: { health_status: { order: 'desc' } } }
      'closed_at' | 'asc' | { sort: { closed_at: { order: 'asc' } } }
      'closed_at' | 'desc' | { sort: { closed_at: { order: 'desc' } } }
      'due_date' | 'asc' | { sort: { due_date: { order: 'asc' } } }
      'due_date' | 'desc' | { sort: { due_date: { order: 'desc' } } }
      nil | 'created_asc' | { sort: { created_at: { order: 'asc' } } }
      nil | 'created_desc' | { sort: { created_at: { order: 'desc' } } }
      nil | 'updated_asc' | { sort: { updated_at: { order: 'asc' } } }
      nil | 'updated_desc' | { sort: { updated_at: { order: 'desc' } } }
      nil | 'popularity_asc' | { sort: { upvotes: { order: 'asc' } } }
      nil | 'popularity_desc' | { sort: { upvotes: { order: 'desc' } } }
      nil | 'milestone_due_asc' | { sort: { milestone_due_date: { order: 'asc' } } }
      nil | 'milestone_due_desc' | { sort: { milestone_due_date: { order: 'desc' } } }
      nil | 'weight_asc' | { sort: { weight: { order: 'asc' } } }
      nil | 'weight_desc' | { sort: { weight: { order: 'desc' } } }
      nil | 'health_status_asc' | { sort: { health_status: { order: 'asc' } } }
      nil | 'health_status_desc' | { sort: { health_status: { order: 'desc' } } }
      nil | 'closed_at_asc' | { sort: { closed_at: { order: 'asc' } } }
      nil | 'closed_at_desc' | { sort: { closed_at: { order: 'desc' } } }
      nil | 'due_date_asc' | { sort: { due_date: { order: 'asc' } } }
      nil | 'due_date_desc' | { sort: { due_date: { order: 'desc' } } }
      'title' | 'asc' | { sort: { 'title.keyword': { order: 'asc' }, id: { order: 'desc' } } }
      'title' | 'desc' | { sort: { 'title.keyword': { order: 'desc' }, id: { order: 'desc' } } }
      nil | 'title_asc' | { sort: { 'title.keyword': { order: 'asc' }, id: { order: 'desc' } } }
      nil | 'title_desc' | { sort: { 'title.keyword': { order: 'desc' }, id: { order: 'desc' } } }
    end

    with_them do
      let(:options) { { order_by: order_by, sort: sort } }

      it { is_expected.to eq(expected) }
    end
  end

  describe 'SORT_MAPPINGS' do
    let(:mappings) { ::Search::Elastic::Types::WorkItem.mappings[:properties] }
    let(:sorted_fields) { described_class::SORT_MAPPINGS.values.flat_map(&:keys).uniq }

    it 'only sorts on fields present in the work item index mapping' do
      missing = sorted_fields.reject do |field|
        root, sub_field = field.to_s.split('.', 2)
        next false unless mappings.key?(root.to_sym)

        sub_field.nil? || mappings.dig(root.to_sym, :fields, sub_field.to_sym).present?
      end

      expect(missing).to be_empty
    end

    # Titles are not unique, and the REST /search path pages with from/size rather than through
    # Search::Elastic::Pagination, so without a second key tied titles have no total order and
    # adjacent pages can repeat or drop rows. `id: desc` also matches the PostgreSQL path's
    # tie-break direction (lib/gitlab/search_results.rb order_title_asc/order_title_desc).
    it 'tie-breaks the title sorts on id descending' do
      %i[title_asc title_desc].each do |key|
        expect(described_class::SORT_MAPPINGS[key].keys.last).to eq(:id)
        expect(described_class::SORT_MAPPINGS[key][:id]).to eq(order: 'desc')
      end
    end
  end

  describe 'MIGRATION_GATED_SORT_KEYS' do
    it 'names migrations that exist and are not obsolete' do
      described_class::MIGRATION_GATED_SORT_KEYS.each_value do |migration_name|
        expect { ::Elastic::DataMigrationService.find_by_name!(migration_name) }.not_to raise_error
      end
    end

    it 'only gates keys SORT_MAPPINGS can answer' do
      expect(described_class::SORT_MAPPINGS.keys)
        .to include(*described_class::MIGRATION_GATED_SORT_KEYS.keys)
    end
  end

  describe '.sort_available?' do
    context 'when the backfill migration has finished' do
      it 'reports the title sort keys as available' do
        expect(described_class.sort_available?(nil, 'title_asc')).to be(true)
        expect(described_class.sort_available?('title', 'desc')).to be(true)
      end
    end

    context 'when the backfill migration has not finished' do
      before do
        allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
          .with(:backfill_title_keyword_in_work_items).and_return(false)
      end

      it 'reports the title sort keys as unavailable' do
        expect(described_class.sort_available?(nil, 'title_asc')).to be(false)
        expect(described_class.sort_available?(nil, 'title_desc')).to be(false)
        expect(described_class.sort_available?('title', 'asc')).to be(false)
      end

      it 'leaves ungated sort keys available' do
        expect(described_class.sort_available?(nil, 'created_asc')).to be(true)
        expect(described_class.sort_available?(nil, 'weight_asc')).to be(true)
        expect(described_class.sort_available?(nil, 'not_a_sort_key')).to be(true)
      end
    end
  end

  describe '#sort_by when the backfill migration has not finished' do
    subject(:sort_by) { described_class.sort_by(query_hash: query_hash, options: options) }

    before do
      allow(::Elastic::DataMigrationService).to receive(:migration_has_finished?)
        .with(:backfill_title_keyword_in_work_items).and_return(false)
    end

    %w[title_asc title_desc].each do |sort|
      context "with #{sort}" do
        let(:options) { { order_by: nil, sort: sort } }

        # Not an empty hash and not a missing key: Pagination#sort_property calls `each_key` on
        # query_hash[:sort] with no nil guard (ee/lib/search/elastic/pagination.rb:155).
        it 'falls back to the default sort rather than sorting on the unpopulated sub-field' do
          expect(sort_by).to eq(sort: { created_at: { order: 'desc' } })
        end

        # This path answers the request in an order it did not ask for, and callers here cannot
        # re-route. Without the log line the substitution is invisible in production.
        # Every key is a `Labkit::Fields` constant: LabKit's field-standardization check fails
        # the build on the deprecated `class`/`msg` spellings in new code. The sort specifics
        # have no standard field of their own, so they nest under ADDITIONAL_DETAILS.
        it 'logs the substitution' do
          expect(::Gitlab::AppLogger).to receive(:warn).with(
            Labkit::Fields::LOG_MESSAGE => 'search sort key unavailable, falling back',
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::ADDITIONAL_DETAILS => {
              requested_sort_key: sort.to_sym,
              fallback_sort_key: :created_at_desc,
              pending_migration: :backfill_title_keyword_in_work_items
            }
          )

          sort_by
        end
      end
    end

    context 'with an ungated sort key' do
      let(:options) { { order_by: nil, sort: 'weight_asc' } }

      it 'is unaffected' do
        expect(sort_by).to eq(sort: { weight: { order: 'asc' } })
      end

      it 'does not log a substitution' do
        expect(::Gitlab::AppLogger).not_to receive(:warn)

        sort_by
      end
    end
  end
end
