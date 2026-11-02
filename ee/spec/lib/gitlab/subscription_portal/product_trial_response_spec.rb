# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::SubscriptionPortal::ProductTrialResponse, feature_category: :knowledge_graph do
  describe '#initialize' do
    it 'accepts every known state' do
      described_class::STATES.each do |state|
        expect { described_class.new(state: state) }.not_to raise_error
      end
    end

    it 'rejects an unknown state' do
      expect { described_class.new(state: :something_else) }
        .to raise_error(ArgumentError, /Unknown CDot state/)
    end
  end

  describe '#trial_active? and #trial_ended?' do
    using RSpec::Parameterized::TableSyntax

    where(:state, :credits_remaining, :active, :ended) do
      :trial          | nil   | true  | false
      :trial          | 0.0   | false | true
      :trial          | 0.5   | true  | false
      :trial          | 100.0 | true  | false
      :expired        | nil   | false | true
      :expired        | 0.0   | false | true
      :expired        | 0.5   | false | true
      :expired        | 100.0 | false | true
      :trial_eligible | nil   | false | false
      :trial_eligible | 100.0 | false | false
      :ineligible     | nil   | false | false
      :ineligible     | 100.0 | false | false
    end

    with_them do
      subject(:response) { described_class.new(state: state, credits_remaining: credits_remaining) }

      it 'derives the lifecycle predicates from state and credits', :aggregate_failures do
        expect(response.trial_active?).to eq(active)
        expect(response.trial_ended?).to eq(ended)
      end
    end
  end

  describe 'error hierarchy' do
    it 'puts UnavailableError under Error, and neither under the Secrets Manager errors', :aggregate_failures do
      expect(described_class::Error.superclass).to eq(Gitlab::SubscriptionPortal::CdotResponseError)
      expect(described_class::UnavailableError.superclass).to eq(described_class::Error)
      expect(described_class::Error).not_to be <= Gitlab::SubscriptionPortal::SecretsManagerResponseError
    end
  end
end
