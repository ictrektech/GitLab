# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::SyncService, feature_category: :software_composition_analysis do
  describe '#execute' do
    let(:connector) { instance_double(Gitlab::PackageMetadata::Connector::Gcp, data_after: [file1, file2]) }
    let(:file1) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(StringIO.new, 1675363107, 0) }
    let(:file2) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(StringIO.new, 1675366673, 0) }
    let(:should_stop) { false }
    let(:stop_signal) { double('stop signal', stop?: should_stop) } # rubocop:disable RSpec/VerifiedDoubles
    let(:data_objects) { build_list(:pm_compressed_data_object, 3, purl_type: sync_config.purl_type) }

    let(:service) { described_class.new(sync_config, stop_signal) }
    let(:sync_config) { build(:pm_sync_config, version_format: 'v2') }

    subject(:execute) { service.execute }

    before do
      allow(PackageMetadata::DataObjectFabricator).to receive(:new)
        .with(data_file: file1, sync_config: sync_config).and_return(data_objects)
      allow(PackageMetadata::DataObjectFabricator).to receive(:new)
        .with(data_file: file2, sync_config: sync_config).and_return(data_objects)
      allow(Gitlab::PackageMetadata::Connector::Gcp).to receive(:new).and_return(connector)
      allow(Gitlab::PackageMetadata::Connector::Offline).to receive(:new).and_return(connector)
      allow(PackageMetadata::Ingestion::CompressedPackage::IngestionService).to receive(:execute)
      allow(PackageMetadata::Ingestion::Advisory::IngestionService).to receive(:execute)
      allow(PackageMetadata::Ingestion::CveEnrichment::IngestionService).to receive(:execute)
      allow(service).to receive(:sleep)
      allow(Gitlab::AppJsonLogger).to receive(:debug)
    end

    shared_examples_for 'it syncs imported data' do
      let(:checkpoint) do
        PackageMetadata::Checkpoint.first_or_initialize(purl_type: sync_config.purl_type,
          version_format: sync_config.version_format, data_type: sync_config.data_type)
      end

      it 'calls connector with the correct checkpoint' do
        execute
        expect(connector).to have_received(:data_after).with(checkpoint)
      end

      context 'when ingesting' do
        context 'if data_type is licenses' do
          it 'calls compressed package ingestion service to store data' do
            execute
            expect(PackageMetadata::Ingestion::CompressedPackage::IngestionService)
              .to have_received(:execute).with(data_objects).twice
          end
        end

        context 'if data_type is advisories' do
          before do
            sync_config.data_type = 'advisories'
          end

          it 'calls advisories ingestion service to store data' do
            execute
            expect(PackageMetadata::Ingestion::Advisory::IngestionService)
              .to have_received(:execute).with(data_objects).twice
          end
        end

        context 'if data_type is cve enrichment' do
          before do
            sync_config.data_type = 'cve_enrichment'
          end

          it 'calls cve enrichment ingestion service to store data' do
            execute
            expect(PackageMetadata::Ingestion::CveEnrichment::IngestionService)
              .to have_received(:execute).with(data_objects).twice
          end
        end
      end

      context 'when a slice has been ingested' do
        context 'and it is in dev mode' do
          before do
            stub_env('PM_SYNC_IN_DEV', 'true')
          end

          it 'throttles calls to ingestion service after each ingested slice' do
            expect(service).not_to receive(:sleep)
            service.execute
          end
        end

        context 'and it is not in dev mode' do
          it 'throttles calls to ingestion service after each ingested slice' do
            expect(service).to receive(:sleep).with(described_class::THROTTLE_RATE).twice
            service.execute
          end
        end
      end

      it 'logs progress with correct sync position' do
        service.execute
        expect(Gitlab::AppJsonLogger).to have_received(:debug)
          .with(hash_including(message: "Evaluating data for #{sync_config}/#{file1}")).once
        expect(Gitlab::AppJsonLogger).to have_received(:debug)
          .with(hash_including(message: "Evaluating data for #{sync_config}/#{file2}")).once
      end
    end

    context 'when checkpoint exists' do
      let(:checkpoint) do
        create(:pm_checkpoint, purl_type: sync_config.purl_type, version_format: sync_config.version_format,
          data_type: sync_config.data_type)
      end

      it_behaves_like 'it syncs imported data'

      it 'updates the checkpoint to the last returned file' do
        expect { execute }.to change { [checkpoint.reload.sequence, checkpoint.reload.chunk] }
          .from([checkpoint.sequence, checkpoint.chunk]).to([file2.sequence, file2.chunk])
      end
    end

    context 'when checkpoint does not exist' do
      it_behaves_like 'it syncs imported data'

      it 'stores the last returned file in a new checkpoint' do
        expect { execute }.to change { PackageMetadata::Checkpoint.count }
          .from(0).to(1)

        checkpoint = PackageMetadata::Checkpoint.where(purl_type: sync_config.purl_type,
          version_format: sync_config.version_format, data_type: sync_config.data_type)
          .first
        expect(checkpoint.sequence).to eq(file2.sequence)
        expect(checkpoint.chunk).to eq(file2.chunk)
      end
    end

    context 'when a data file has no rows' do
      let(:sync_config) { build(:pm_sync_config, version_format: 'v2') }
      let(:empty_file) { Gitlab::PackageMetadata::Connector::NdjsonDataFile.new(StringIO.new, 1675363107, 0) }
      let(:connector) { instance_double(Gitlab::PackageMetadata::Connector::Gcp, data_after: [empty_file]) }

      let!(:checkpoint) do
        create(:pm_checkpoint, purl_type: sync_config.purl_type, version_format: sync_config.version_format,
          data_type: sync_config.data_type)
      end

      before do
        # The outer stubs are pinned to file1/file2; this restores a default for empty_file.
        allow(PackageMetadata::DataObjectFabricator).to receive(:new).and_call_original
      end

      # A chunk reaches the fabricator with zero objects when the export is empty or when
      # every row fails to parse, so the checkpoint must advance or later runs re-read it.
      it 'ingests nothing and still advances the checkpoint', :aggregate_failures do
        expect { execute }.to change { [checkpoint.reload.sequence, checkpoint.reload.chunk] }
          .to([empty_file.sequence, empty_file.chunk])

        expect(PackageMetadata::Ingestion::CompressedPackage::IngestionService).not_to have_received(:execute)
      end
    end

    context 'when an error occurs during execution' do
      let(:seq) { 0 }
      let(:chunk) { 0 }
      let!(:checkpoint) do
        create(:pm_checkpoint, purl_type: sync_config.purl_type, sequence: seq, chunk: chunk)
      end

      before do
        allow(service).to receive(:ingest).and_raise(StandardError)
      end

      it 'does not update the checkpoint so as not to skip the errored file' do
        expect { execute }.to raise_error(StandardError)
        expect([checkpoint.reload.sequence, checkpoint.reload.chunk]).to match_array([seq, chunk])
      end
    end

    context 'when the stop signal fires after the first file' do
      before do
        allow(stop_signal).to receive(:stop?).and_return(false, true)
      end

      it 'terminates after checkpointing' do
        execute
        checkpoint = PackageMetadata::Checkpoint.where(purl_type: sync_config.purl_type,
          version_format: sync_config.version_format, data_type: sync_config.data_type).first
        expect(checkpoint.sequence).to eq(file1.sequence)
        expect(checkpoint.chunk).to eq(file1.chunk)
        expect(PackageMetadata::Ingestion::CompressedPackage::IngestionService)
          .to have_received(:execute).with(data_objects).once
      end
    end

    context 'when the stop signal fires before the first file' do
      let(:should_stop) { true }

      let!(:checkpoint) do
        create(:pm_checkpoint, purl_type: sync_config.purl_type, version_format: sync_config.version_format,
          data_type: sync_config.data_type)
      end

      it 'ingests nothing and leaves the checkpoint for the next run', :aggregate_failures do
        expect { execute }.not_to change { [checkpoint.reload.sequence, checkpoint.reload.chunk] }

        expect(PackageMetadata::Ingestion::CompressedPackage::IngestionService).not_to have_received(:execute)
      end
    end

    context 'when the data type is cve_enrichment' do
      let(:sync_config) { build(:pm_sync_config, data_type: 'cve_enrichment', version_format: 'v2', purl_type: nil) }
      let(:cve_checkpoint) do
        PackageMetadata::Checkpoint.find_by(data_type: 'cve_enrichment', version_format: 'v2', purl_type: nil)
      end

      context 'when no pass through the export is under way' do
        it 'reads the export from its first file' do
          execute

          expect(connector).to have_received(:data_after).with(nil)
        end

        it 'records the pass as complete once the files run out' do
          execute

          expect(cve_checkpoint).to have_attributes(sequence: file2.sequence, chunk: file2.chunk,
            full_sync_target_sequence: nil)
        end
      end

      context 'when a pass through the export is under way' do
        let!(:checkpoint) do
          create(:pm_checkpoint, data_type: 'cve_enrichment', version_format: 'v2', purl_type: nil,
            sequence: file1.sequence, chunk: file1.chunk, full_sync_target_sequence: file1.sequence)
        end

        it 'resumes the pass from its checkpoint' do
          execute

          expect(connector).to have_received(:data_after).with(checkpoint)
        end
      end

      context 'when the stop signal fires before the last file' do
        before do
          allow(stop_signal).to receive(:stop?).and_return(false, true)
        end

        it 'records the pass as under way at the last file it ingested' do
          execute

          expect(cve_checkpoint).to have_attributes(sequence: file1.sequence, chunk: file1.chunk,
            full_sync_target_sequence: file1.sequence)
        end
      end
    end

    context 'when storage_type is gcp' do
      let(:sync_config) { build(:pm_sync_config, storage_type: :gcp) }

      it_behaves_like 'it syncs imported data'
    end

    context 'when storage_type is offline' do
      let(:sync_config) { build(:pm_sync_config, storage_type: :offline) }

      it_behaves_like 'it syncs imported data'
    end

    context 'when storage_type is unknown' do
      let(:sync_config) { build(:pm_sync_config, storage_type: :foo) }

      it 'raises an error' do
        expect { execute }.to raise_error(described_class::UnknownAdapterError)
      end
    end
  end

  describe '.execute' do
    let(:observer) { instance_double(described_class) }
    let(:lease) { instance_double(Gitlab::ExclusiveLease) }
    let(:stop_signal) { instance_double(PackageMetadata::StopSignal, stop?: should_stop) }
    let(:enabled_purl_types) { ApplicationSetting.create_from_defaults.package_metadata_purl_types_names }
    let(:max_lease_length) { described_class::MAX_LEASE_LENGTH }

    subject(:execute) { described_class.execute(data_type: data_type, lease: lease) }

    before do
      allow(PackageMetadata::StopSignal).to receive(:new)
        .with(lease, max_lease_length, described_class::MAX_SYNC_DURATION)
        .and_return(stop_signal)
    end

    shared_examples_for 'it calls #execute for each enabled config' do
      let(:should_stop) { false }

      specify do
        expect(observer).to receive(:execute).exactly(enabled_purl_types.size).times
        enabled_purl_types.each do |purl_type, _|
          expect(described_class).to receive(:new)
            .with(having_attributes(data_type: data_type, purl_type: purl_type), stop_signal)
            .and_return(observer)
        end
        execute
      end
    end

    context 'when stop_signal.stop? is false' do
      context 'and the data_type is licenses' do
        let(:data_type) { 'licenses' }

        it_behaves_like 'it calls #execute for each enabled config'
      end

      context 'and the data_type is advisories' do
        let(:data_type) { 'advisories' }

        it_behaves_like 'it calls #execute for each enabled config'
      end

      context 'and the data_type is cve_enrichment' do
        let(:data_type) { 'cve_enrichment' }
        let(:max_lease_length) { described_class::CVE_ENRICHMENT_MAX_LEASE_LENGTH }
        let(:should_stop) { false }

        it 'calls #execute once' do
          expect(observer).to receive(:execute).once
          expect(described_class).to receive(:new)
            .with(having_attributes(data_type: data_type, purl_type: nil), stop_signal)
            .and_return(observer)
          execute
        end
      end
    end

    context 'when stop_signal.stop? is true' do
      let(:should_stop) { true }
      let(:data_type) { 'licenses' }

      it 'does not proceed' do
        expect(described_class).not_to receive(:new)
        execute
      end
    end
  end

  describe 'syncing a CVE enrichment export across runs' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:sync_config) { PackageMetadata::SyncConfiguration.new('cve_enrichment', :offline, tmpdir, 'v2', nil) }
    let(:signal) { instance_double(PackageMetadata::StopSignal) }
    let(:runs) { [] }

    def chunk_path(chunk)
      File.join(tmpdir, 'v2', 'cve_enrichment', '0', format('%09d.ndjson', chunk))
    end

    def write_chunk(chunk, *cve_ids)
      FileUtils.mkdir_p(File.dirname(chunk_path(chunk)))
      rows = cve_ids.map { |cve_id| "#{Gitlab::Json.dump(cve_id: cve_id, epss_score: 0.1)}\n" }
      File.write(chunk_path(chunk), rows.join)
    end

    def run_sync
      runs << []
      described_class.new(sync_config, signal).execute
    end

    before do
      stub_env('PM_SYNC_IN_DEV', 'true')
      allow(Gitlab::AppJsonLogger).to receive(:debug)
      allow(signal).to receive(:stop?) { runs.last.any? }
      allow(PackageMetadata::Ingestion::CveEnrichment::IngestionService).to receive(:execute) do |data_objects|
        runs.last.concat(data_objects.map(&:cve_id))
      end

      write_chunk(0, 'CVE-2020-0001')
      write_chunk(1, 'CVE-2024-0001')
    end

    after do
      FileUtils.remove_entry(tmpdir)
    end

    it 'resumes each run at the chunk after the last one it read' do
      2.times { run_sync }

      expect(runs).to eq([%w[CVE-2020-0001], %w[CVE-2024-0001]])
    end

    it 'reads a rewritten export again from its first chunk once a pass completes' do
      2.times { run_sync }
      write_chunk(0, 'CVE-2020-0001', 'CVE-2020-0002')
      write_chunk(1, 'CVE-2024-0001', 'CVE-2024-0002')
      2.times { run_sync }

      expect(runs.last(2)).to eq([%w[CVE-2020-0001 CVE-2020-0002], %w[CVE-2024-0001 CVE-2024-0002]])
    end

    it 'stops cleanly before a listed file that was removed during the run' do
      write_chunk(99, 'CVE-1999-0001')
      allow(PackageMetadata::Ingestion::CveEnrichment::IngestionService).to receive(:execute) do |data_objects|
        runs.last.concat(data_objects.map(&:cve_id))
        FileUtils.rm_f(chunk_path(99)) if runs.size == 2
      end

      2.times { run_sync }

      expect(runs).to eq([%w[CVE-2020-0001], %w[CVE-2024-0001]])
    end
  end

  describe 'connector selection' do
    let(:signal) { instance_double(PackageMetadata::StopSignal) }

    # Drive the public #execute path and assert which connector it builds,
    # rather than reaching into the private #connector method.
    def expect_sync_via(connector_class)
      connector = instance_double(connector_class, data_after: [])
      expect(connector_class).to receive(:new).with(sync_config).and_return(connector)

      described_class.new(sync_config, signal).execute
    end

    context 'when storage_type is offline' do
      let(:sync_config) { build(:pm_sync_config, storage_type: :offline, data_type: 'advisories') }

      it 'syncs through the offline connector' do
        expect_sync_via(Gitlab::PackageMetadata::Connector::Offline)
      end
    end
  end
end
