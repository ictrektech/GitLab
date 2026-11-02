# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::AdvisoryV3SyncService, feature_category: :software_composition_analysis do
  it_behaves_like 'a v3 sync service'

  describe 'the log vocabulary' do
    # log_event is what dashboards and searches key on, so it is pinned in the
    # subclass rather than derived from data_type in the base class.
    it 'names the dataset the way the logs and the label do', :aggregate_failures do
      expect(described_class.log_event).to eq('advisory_sync')
      expect(described_class.dataset_label).to eq('Advisory')
    end
  end

  describe 'the run budget' do
    # The worker's lease, the sync window and the throttle are a set: the window
    # has to stay under the lease so a run stops before the lease expires.
    it 'keeps the sync window inside the lease', :aggregate_failures do
      expect(described_class.max_lease_length).to eq(22.minutes)
      expect(described_class.max_sync_duration).to eq(20.minutes)
      expect(described_class.max_sync_duration).to be < described_class.max_lease_length
    end

    it 'ingests in slices and throttles between them', :aggregate_failures do
      expect(described_class.ingest_slice_size).to eq(1_000)
      expect(described_class.throttle_rate).to eq(0.25.seconds)
    end
  end

  describe 'the ingestion pieces' do
    # Advisories reuse the v2 ingestion pipeline and the shared fabricator.
    it 'reuses the existing advisory pipeline', :aggregate_failures do
      expect(described_class.fabricator_class).to eq(PackageMetadata::DataObjectFabricator)
      expect(described_class.ingestion_service).to eq(PackageMetadata::Ingestion::Advisory::IngestionService)
    end
  end
end
