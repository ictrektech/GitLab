# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::RowBackfill, feature_category: :team_planning do
  let_it_be(:group) { create(:group) }

  it 'reports the legacy rows as rewritten' do
    expect(described_class.legacy_rows_rewritten?(group)).to be(true)
  end

  it 'reports rows complete for the backfilled base types only' do
    expect(described_class.rows_complete_for?(group, :issue)).to be(true)
    expect(described_class.rows_complete_for?(group, 'task')).to be(true)
    expect(described_class.rows_complete_for?(group, :epic)).to be(false)
    expect(described_class.rows_complete_for?(group, :incident)).to be(false)
    expect(described_class.rows_complete_for?(group, nil)).to be(false)
  end

  it 'checks the flag against the root namespace when given a subgroup' do
    subgroup = create(:group, parent: group)
    stub_feature_flags(work_item_status_single_column_filter: group)

    expect(described_class.enabled_for?(subgroup)).to be(true)
    expect(described_class.enabled_for?(create(:group))).to be(false)
  end

  it 'reports nothing as complete without a namespace' do
    expect(described_class.legacy_rows_rewritten?(nil)).to be(false)
    expect(described_class.rows_complete_for?(nil, :issue)).to be(false)
  end

  context 'when the flag is disabled for the namespace' do
    before do
      stub_feature_flags(work_item_status_single_column_filter: false)
    end

    it 'reports nothing as complete' do
      expect(described_class.legacy_rows_rewritten?(group)).to be(false)
      expect(described_class.rows_complete_for?(group, :issue)).to be(false)
    end
  end
end
