# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::TrialUsage, feature_category: :acquisition do
  subject(:trial_usage) { build(:gitlab_subscription_trial_usage) }

  it { is_expected.to include_module(EachBatch) }
  it { is_expected.to include_module(PartitionedTable) }

  describe 'partitioning' do
    it 'partitions monthly by trial end date and keeps two years of snapshots', :aggregate_failures do
      strategy = described_class.partitioning_strategy

      expect(strategy).to be_a(Gitlab::Database::Partitioning::Time::MonthlyStrategy)
      expect(strategy.partitioning_key).to eq(:trial_ends_on)
      expect(strategy.retain_for).to eq(24.months)
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).required }
  end

  describe 'validations' do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:trial_starts_on) }
    it { is_expected.to validate_presence_of(:trial_ends_on) }
    it { is_expected.to validate_presence_of(:compute_minutes_month) }
    it { is_expected.to validate_length_of(:trial_type).is_at_most(255) }

    it 'validates max_seats_used is a non-negative integer' do
      is_expected.to validate_numericality_of(:max_seats_used).only_integer.is_greater_than_or_equal_to(0)
    end

    it 'validates compute_minutes_used is a non-negative integer' do
      is_expected.to validate_numericality_of(:compute_minutes_used).only_integer.is_greater_than_or_equal_to(0)
    end

    it { is_expected.to validate_numericality_of(:credits_used).is_greater_than_or_equal_to(0).allow_nil }

    it 'rejects a trial that does not end after it starts', :aggregate_failures do
      trial_usage.trial_starts_on = Date.current
      trial_usage.trial_ends_on = Date.current

      expect(trial_usage).not_to be_valid
      expect(trial_usage.errors.of_kind?(:trial_ends_on, :greater_than)).to be(true)
    end

    it 'rejects a second snapshot for the same namespace and trial end date', :aggregate_failures do
      existing = create(:gitlab_subscription_trial_usage)
      duplicate = build(
        :gitlab_subscription_trial_usage,
        namespace: existing.namespace,
        trial_ends_on: existing.trial_ends_on
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:trial_ends_on]).to include('has already been taken')
    end

    it 'allows one snapshot per trial for a namespace that trialled more than once' do
      existing = create(:gitlab_subscription_trial_usage)
      retrial = build(
        :gitlab_subscription_trial_usage,
        namespace: existing.namespace,
        trial_starts_on: existing.trial_ends_on + 90.days,
        trial_ends_on: existing.trial_ends_on + 120.days
      )

      expect(retrial).to be_valid
    end
  end

  describe '.for_namespace' do
    let_it_be(:namespace) { create(:group) }
    let_it_be(:other_namespace) { create(:group) }
    let_it_be(:trial_usage) { create(:gitlab_subscription_trial_usage, namespace: namespace) }

    before_all do
      create(:gitlab_subscription_trial_usage, namespace: other_namespace)
    end

    it 'returns only the snapshots for the given namespace' do
      expect(described_class.for_namespace(namespace)).to contain_exactly(trial_usage)
    end
  end

  describe '.find_for_trial' do
    let_it_be(:namespace) { create(:group) }
    let_it_be(:trial_usage) { create(:gitlab_subscription_trial_usage, namespace: namespace) }

    it 'returns the snapshot for the namespace and trial end date', :aggregate_failures do
      expect(described_class.find_for_trial(namespace.id, trial_usage.trial_ends_on)).to eq(trial_usage)
      expect(described_class.find_for_trial(namespace.id, trial_usage.trial_ends_on + 1)).to be_nil
    end
  end
end
