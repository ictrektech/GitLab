# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::CandidateMetric, feature_category: :mlops do
  describe 'associations' do
    it { is_expected.to belong_to(:candidate) }
  end

  describe 'scope :latest' do
    let_it_be(:candidate) { create(:ml_candidates) }
    let!(:metric1) { create(:ml_candidate_metrics, candidate: candidate) }
    let!(:metric2) { create(:ml_candidate_metrics, candidate: candidate) }
    let!(:metric3) { create(:ml_candidate_metrics, name: metric1.name, candidate: candidate) }

    subject { described_class.latest }

    it 'fetches only the last metric for the name' do
      expect(subject).to match_array([metric2, metric3])
    end
  end

  describe 'scope :most_recent_for_candidate' do
    let_it_be(:candidate) { create(:ml_candidates) }
    let_it_be(:other_candidate) { create(:ml_candidates) }
    let_it_be(:metrics) do
      Array.new(4) do
        create(:ml_candidate_metrics, candidate: other_candidate)
        create(:ml_candidate_metrics, candidate: candidate)
      end
    end

    it 'returns the most recent rows of the candidate, newest first' do
      expect(described_class.most_recent_for_candidate(candidate.id, 3)).to eq(metrics.last(3).reverse)
    end

    it 'returns every row of the candidate when the limit is larger' do
      expect(described_class.most_recent_for_candidate(candidate.id, 10)).to eq(metrics.reverse)
    end
  end
end
