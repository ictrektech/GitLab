# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::WorkItems::Features::LinkedItems, feature_category: :portfolio_management do
  it_behaves_like 'work item widget entity parity',
    described_class,
    Types::WorkItems::Widgets::LinkedItemsType,
    exceptions: %w[linked_items blocked]

  describe '#as_json' do
    let(:work_item) { build_stubbed(:work_item, blocking_issues_count: 2) }
    let(:widget) { instance_double(WorkItems::Widgets::LinkedItems, work_item: work_item) }
    let(:blocked_by_counts) { { work_item.id => 1 } }

    subject(:representation) { described_class.new(widget, blocked_by_counts: blocked_by_counts).as_json }

    it 'exposes the blocking count from the counter cache' do
      expect(representation[:blocking_count]).to eq(2)
    end

    it 'exposes the blocked by count from the pre-computed counts' do
      expect(representation[:blocked_by_count]).to eq(1)
    end

    context 'when there is no pre-computed count for the work item' do
      let(:blocked_by_counts) { {} }

      it 'returns zero' do
        expect(representation[:blocked_by_count]).to eq(0)
      end
    end

    context 'when the blocked_by_counts option is not provided' do
      subject(:representation) { described_class.new(widget).as_json }

      it 'returns zero' do
        expect(representation[:blocked_by_count]).to eq(0)
      end
    end
  end
end
