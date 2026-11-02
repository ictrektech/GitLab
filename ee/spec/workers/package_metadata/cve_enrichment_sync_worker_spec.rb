# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::CveEnrichmentSyncWorker, feature_category: :software_composition_analysis do
  describe '#perform' do
    let(:instance) { described_class.new }
    let(:lease) { instance_double(Gitlab::ExclusiveLease) }

    subject(:perform!) { instance.perform }

    before do
      allow(instance).to receive(:try_obtain_lease).and_yield
      allow(Gitlab::ExclusiveLease).to receive(:new).and_return(lease)
    end

    shared_examples_for 'it syncs' do
      context 'when security_orchestration_policies feature is available' do
        before do
          stub_licensed_features(dependency_scanning: true, security_orchestration_policies: true)
        end

        it 'calls sync service with the cve_enrichment data_type and enqueues SyncFindingEnrichmentWorker' do
          expect(PackageMetadata::SyncService).to receive(:execute).with(data_type: 'cve_enrichment', lease: lease)

          expect(Security::SyncFindingEnrichmentWorker).to receive(:perform_async)

          perform!
        end
      end

      context 'when security_orchestration_policies feature is not available' do
        before do
          stub_licensed_features(dependency_scanning: true, security_orchestration_policies: false)
        end

        it 'calls sync service with the cve_enrichment data_type and does not enqueue SyncFindingEnrichmentWorker' do
          expect(PackageMetadata::SyncService).to receive(:execute).with(data_type: 'cve_enrichment', lease: lease)

          expect(Security::SyncFindingEnrichmentWorker).not_to receive(:perform_async)

          perform!
        end
      end
    end

    shared_examples_for 'it does not sync' do
      it 'does not call sync service' do
        expect(PackageMetadata::SyncService).not_to receive(:execute)

        perform!
      end
    end

    context 'when the dependency_scanning feature is disabled' do
      before do
        stub_licensed_features(dependency_scanning: false)
      end

      it_behaves_like 'it does not sync'
    end

    context 'when the dependency_scanning feature is enabled' do
      before do
        stub_licensed_features(dependency_scanning: true)
      end

      context 'and rails is not development' do
        before do
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        it_behaves_like 'it syncs'
      end

      context 'and rails is development' do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        context 'and sync in dev env variable is true' do
          before do
            stub_env('PM_SYNC_IN_DEV', true)
          end

          it_behaves_like 'it syncs'
        end

        context 'and sync in dev env variable is false' do
          before do
            stub_env('PM_SYNC_IN_DEV', false)
          end

          it_behaves_like 'it does not sync'
        end
      end
    end
  end

  describe 'exclusive lease', :clean_gitlab_redis_shared_state do
    let(:lease_key) { Gitlab::ExclusiveLease.redis_shared_state_key(described_class.name.underscore) }
    # A file at the export's size limit, ingested at THROTTLE_RATE.
    let(:file_ingest_time) { 50.minutes }
    let(:runs) { [] }

    # Redis expiry cannot be time-travelled, so shorten the lease as the clock would.
    def let_time_pass(duration)
      Gitlab::Redis::SharedState.with do |redis|
        remaining = redis.pttl(lease_key) - duration.in_milliseconds
        remaining > 0 ? redis.pexpire(lease_key, remaining.to_i) : redis.del(lease_key)
      end
    end

    def during_each_run
      allow(PackageMetadata::SyncService).to receive(:new).and_wrap_original do |_original, _config, signal|
        instance_double(PackageMetadata::SyncService).tap do |run|
          allow(run).to receive(:execute) do
            runs << signal
            yield(signal) if block_given?
          end
        end
      end
    end

    before do
      stub_licensed_features(dependency_scanning: true)
      allow(Rails.env).to receive(:development?).and_return(false)
    end

    it 'stops the run once the sync budget is spent, not before', :aggregate_failures do
      stopped = []
      during_each_run do |signal|
        let_time_pass(PackageMetadata::SyncService::MAX_SYNC_DURATION - 30.seconds)
        stopped << signal.stop?
        let_time_pass(1.minute)
        stopped << signal.stop?
      end

      described_class.new.perform

      expect(stopped).to eq([false, true])
    end

    it 'keeps other runs out until a file started at the end of the budget is ingested' do
      during_each_run do
        next unless runs.one?

        let_time_pass(PackageMetadata::SyncService::MAX_SYNC_DURATION + file_ingest_time)
        described_class.new.perform
      end

      described_class.new.perform

      expect(runs.size).to eq(1)
    end

    it 'lets the next hourly run in when a killed run never released its lease' do
      Gitlab::ExclusiveLease.new(described_class.name.underscore, timeout: described_class::LEASE_TIMEOUT).try_obtain
      let_time_pass(1.hour)
      during_each_run

      described_class.new.perform

      expect(runs.size).to eq(1)
    end
  end
end
