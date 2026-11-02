# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Ml::CandidateFinder, feature_category: :mlops do
  let_it_be(:experiment) { create(:ml_experiments, user: nil) }

  let_it_be(:candidates) do
    %w[c a da b].zip([3, 2, 4, 1]).map do |name, auc|
      make_candidate_and_metric(name, auc, experiment)
    end
  end

  let_it_be(:another_candidate) { create(:ml_candidates) }
  let_it_be(:first_candidate) { candidates.first }

  let(:finder) { described_class.new(experiment, params) }
  let(:page) { 1 }
  let(:default_params) { { page: page } }
  let(:params) { default_params }

  subject { finder.execute }

  describe '.execute' do
    describe 'by name' do
      context 'when params has no name' do
        it 'fetches all candidates in the experiment' do
          expect(subject).to match_array(candidates)
        end

        it 'does not fetch candidate not in experiment' do
          expect(subject).not_to include(another_candidate)
        end
      end

      context 'when name is included in params' do
        let(:params) { { name: 'a' } }

        it 'fetches the correct candidates' do
          expect(subject).to match_array(candidates.values_at(2, 1))
        end
      end
    end

    describe 'sorting' do
      using RSpec::Parameterized::TableSyntax

      where(:test_case, :order_by, :order_by_type, :direction, :expected_order) do
        'default params' | nil | nil |  nil | [3, 2, 1, 0]
        'ascending order' | nil | nil | 'ASC' | [0, 1, 2, 3]
        'column is passed' | 'name' | 'column' | 'ASC' | [1, 3, 0, 2]
        'column is a metric' | 'auc' | 'metric' | nil | [2, 0, 1, 3]
        'invalid sort' | nil | nil | 'INVALID' | [3, 2, 1, 0]
        'invalid order by' | 'INVALID' | 'column' | 'desc' | [3, 2, 1, 0]
        'invalid order by metric' | nil | 'metric' | 'desc' | []
      end
      with_them do
        let(:params) { { order_by: order_by, order_by_type: order_by_type, sort: direction } }

        it { expect(subject).to eq(candidates.values_at(*expected_order)) }
      end
    end

    context 'when name and sort by metric is passed' do
      let(:params) { { order_by: 'auc', order_by_type: 'metric', sort: 'DESC', name: 'a' } }

      it { expect(subject).to eq(candidates.values_at(2, 1)) }
    end

    describe 'sorting by metric with keyset pagination' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:tied_candidates) do
        [3, 3, 2].map.with_index { |auc, i| make_candidate_and_metric("tie#{i}", auc, experiment) }
      end

      let(:params) { { order_by: 'auc', order_by_type: 'metric', sort: direction } }
      let(:expected_order) do
        {
          'desc' => [candidates[2], *tied_candidates.values_at(1, 0), candidates[0], tied_candidates[2],
            candidates[1], candidates[3]],
          'asc' => [candidates[3], tied_candidates[2], candidates[1], *tied_candidates.values_at(1, 0),
            candidates[0], candidates[2]]
        }[direction]
      end

      shared_examples 'paginating by the latest metric value' do
        where(:direction, :per_page) do
          'desc' | 1
          'desc' | 2
          'desc' | 3
          'asc'  | 1
          'asc'  | 2
          'asc'  | 3
        end

        with_them do
          it 'walks the pages forward and back in order, with ties ordered by id', :aggregate_failures do
            forward, backward = walk_pages(per_page: per_page)

            expect(forward.flatten).to eq(expected_order)
            expect(backward).to eq(forward)
          end
        end
      end

      it_behaves_like 'paginating by the latest metric value'

      context 'when ml_candidate_metric_order_lateral is disabled' do
        before do
          stub_feature_flags(ml_candidate_metric_order_lateral: false)
        end

        it_behaves_like 'paginating by the latest metric value'
      end
    end
  end

  describe 'metric ordering join' do
    let(:params) { { order_by: 'auc', order_by_type: 'metric' } }

    it 'joins the latest metric of each candidate laterally' do
      expect(subject.to_sql).to include('INNER JOIN LATERAL')
    end

    context 'when ml_candidate_metric_order_lateral is disabled' do
      before do
        stub_feature_flags(ml_candidate_metric_order_lateral: false)
      end

      it 'joins the latest metrics of all candidates' do
        expect(subject.to_sql).not_to include('LATERAL')
      end
    end

    context 'when the experiment has as many candidates as the lateral join limit' do
      before do
        stub_const("#{described_class}::LATERAL_METRIC_ORDER_MAX_CANDIDATES", candidates.size)
      end

      it 'joins the latest metric of each candidate laterally' do
        expect(subject.to_sql).to include('INNER JOIN LATERAL')
      end
    end

    context 'when the experiment has more candidates than the lateral join limit' do
      before do
        stub_const("#{described_class}::LATERAL_METRIC_ORDER_MAX_CANDIDATES", candidates.size - 1)
      end

      it 'joins the latest metrics of all candidates' do
        expect(subject.to_sql).not_to include('LATERAL')
      end
    end
  end

  private

  def walk_pages(per_page:)
    paginator = finder.execute.keyset_paginate(per_page: per_page)
    forward = [paginator.records.to_a]

    while paginator.has_next_page?
      paginator = finder.execute.keyset_paginate(cursor: paginator.cursor_for_next_page, per_page: per_page)
      forward << paginator.records.to_a
    end

    backward = [forward.last]

    while paginator.has_previous_page?
      paginator = finder.execute.keyset_paginate(cursor: paginator.cursor_for_previous_page, per_page: per_page)
      backward.unshift(paginator.records.to_a)
    end

    [forward, backward]
  end

  def make_candidate_and_metric(name, auc_value, experiment)
    create(:ml_candidates, name: name, experiment: experiment, user: nil).tap do |c|
      create(:ml_candidate_metrics, name: 'auc', candidate_id: c.id, value: 10)
      create(:ml_candidate_metrics, name: 'auc', candidate_id: c.id, value: auc_value)
    end
  end
end
