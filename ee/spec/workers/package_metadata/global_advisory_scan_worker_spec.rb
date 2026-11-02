# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::GlobalAdvisoryScanWorker, feature_category: :software_composition_analysis do
  let_it_be(:advisory) { create(:pm_advisory) }
  let(:event) { PackageMetadata::IngestedAdvisoryEvent.new(data: { advisory_id: advisory.id }) }

  before do
    allow(PackageMetadata::AdvisoryScanService).to receive(:execute)
  end

  it_behaves_like 'subscribes to event'

  describe 'deferring on database health' do
    it 'watches the high-churn vulnerability tables on the sec database' do
      expect(described_class.database_health_check_attrs).to include(
        gitlab_schema: :gitlab_sec,
        tables: %w[
          vulnerability_reads
          vulnerability_occurrences
          vulnerabilities
          vulnerability_identifiers
          vulnerability_occurrence_identifiers
        ],
        delay_by: 5.minutes
      )
    end

    it 'defers when the feature flag is enabled' do
      expect(described_class.defer_on_database_health_signal?).to be(true)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(defer_global_advisory_scan_on_database_health: false)
      end

      it 'does not defer' do
        expect(described_class.defer_on_database_health_signal?).to be(false)
      end
    end
  end

  context 'when advisory exists' do
    it 'calls the advisory scanning service with the instantiated advisory' do
      consume_event(subscriber: described_class, event: event)
      expect(PackageMetadata::AdvisoryScanService).to have_received(:execute).with(advisory)
    end
  end

  context 'when advisory could not be found' do
    before do
      allow(PackageMetadata::Advisory).to receive(:find_by_id)
      .with(event.data[:advisory_id]).and_return(nil)
    end

    it 'logs the error and does not initiate a scan' do
      expect(Sidekiq.logger).to receive(:error).with(hash_including({ 'message' => 'Advisory not found.',
'advisory_id' => advisory.id }))

      consume_event(subscriber: described_class, event: event)
      expect(PackageMetadata::AdvisoryScanService).not_to have_received(:execute)
    end
  end
end
