# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::SyncReason, feature_category: :security_policy_management do
  describe '.from_params' do
    using RSpec::Parameterized::TableSyntax

    where(:params, :expected) do
      nil                                                 | :policy_change
      {}                                                  | :policy_change
      { 'sync_reason' => 'policy_change' }                | :policy_change
      { 'sync_reason' => 'force_resync' }                 | :force_resync
      { 'sync_reason' => 'configuration_assigned' }       | :configuration_assigned
      { sync_reason: :force_resync }                      | :force_resync
      { 'sync_reason' => 'bogus' }                        | :policy_change
      { 'force_resync' => true }                          | :force_resync
      { 'force_resync' => false }                         | :policy_change
      { 'triggered_by_assign' => true }                   | :configuration_assigned
      { force_resync: true, triggered_by_assign: true }   | :force_resync
      { 'sync_reason' => 'bogus', 'force_resync' => true } | :force_resync
    end

    with_them do
      it { expect(described_class.from_params(params)).to eq(expected) }
    end
  end

  describe '.to_params' do
    using RSpec::Parameterized::TableSyntax

    where(:reason, :expected) do
      :policy_change            | { 'sync_reason' => 'policy_change' }
      :force_resync             | { 'sync_reason' => 'force_resync', 'force_resync' => true }
      'force_resync'            | { 'sync_reason' => 'force_resync', 'force_resync' => true }
      :configuration_assigned   | { 'sync_reason' => 'configuration_assigned', 'triggered_by_assign' => true }
    end

    with_them do
      it { expect(described_class.to_params(reason)).to eq(expected) }
    end

    it 'raises for an unknown reason' do
      expect { described_class.to_params(:bogus) }.to raise_error(ArgumentError, /bogus/)
    end

    it 'round-trips through from_params' do
      described_class::REASONS.each do |reason|
        expect(described_class.from_params(described_class.to_params(reason))).to eq(reason)
      end
    end
  end
end
