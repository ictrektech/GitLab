# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SyncScanPoliciesWorker, feature_category: :security_policy_management do
  describe '#perform' do
    let_it_be(:configuration) { create(:security_orchestration_policy_configuration, configured_at: nil) }

    subject(:worker) { described_class.new }

    include_examples 'an idempotent worker' do
      let(:job_args) { [configuration.id, { 'sync_reason' => 'policy_change' }] }
    end

    it 'has the `until_executed` deduplicate strategy' do
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end

    it 'calls SyncPoliciesService' do
      expect_next_instance_of(
        Security::SecurityOrchestrationPolicies::SyncPoliciesService,
        configuration: configuration,
        params: {}
      ) do |service|
        expect(service).to receive(:execute)
      end

      worker.perform(configuration.id)
    end

    it 'does not call SyncPoliciesService when configuration is not present' do
      expect(Security::SecurityOrchestrationPolicies::SyncPoliciesService).not_to receive(:new)

      worker.perform(non_existing_record_id)
    end

    %w[force_resync configuration_assigned].each do |sync_reason|
      context "when sync_reason is #{sync_reason}" do
        it 'passes the sync_reason to SyncPoliciesService' do
          expect_next_instance_of(
            Security::SecurityOrchestrationPolicies::SyncPoliciesService,
            configuration: configuration,
            params: { sync_reason: sync_reason }
          ) do |service|
            expect(service).to receive(:execute)
          end

          worker.perform(configuration.id, { 'sync_reason' => sync_reason })
        end
      end
    end
  end
end
