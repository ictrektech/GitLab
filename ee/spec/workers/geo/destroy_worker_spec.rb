# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::DestroyWorker, :geo, feature_category: :geo_replication do
  include EE::GeoHelpers

  let(:replicator) { double(:replicator) }

  describe '#perform' do
    it 'calls replicator#replicate_destroy' do
      expect(replicator).to receive(:replicate_destroy)

      expect(Gitlab::Geo::Replicator).to receive(:for_replicable_params).with(replicable_name: 'snippet_repository', replicable_id: 1).and_return(replicator)

      described_class.new.perform('snippet_repository', 1)
    end
  end

  describe '#perform for a blob whose model record is gone' do
    let_it_be(:secondary) { create(:geo_node) }

    let!(:lfs_object) { create(:lfs_object, :with_file) }
    let!(:file_path) { lfs_object.file.path }
    let!(:registry) do
      create(:geo_lfs_object_registry, lfs_object_id: lfs_object.id, blob_path: lfs_object.file.relative_path.to_s)
    end

    before do
      stub_current_geo_node(secondary)
      lfs_object.delete
    end

    it 'removes the file using the stored location' do
      expect { described_class.new.perform('lfs_object', lfs_object.id) }
        .to change { File.exist?(file_path) }.from(true).to(false)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(geo_blob_removal_uses_registry_location: false)
      end

      it 'leaves the file in place' do
        expect { described_class.new.perform('lfs_object', lfs_object.id) }
          .not_to change { File.exist?(file_path) }.from(true)
      end
    end
  end

  describe '#perform for an avatar whose upload row was replaced at the same path' do
    let_it_be(:secondary) { create(:geo_node) }

    let!(:old_upload) { create(:upload, :with_file) }
    let!(:file_path) { old_upload.retrieve_uploader.file.path }
    let!(:registry) do
      create(:geo_upload_registry,
        upload: old_upload,
        blob_path: old_upload.retrieve_uploader.relative_path,
        uploader_class: old_upload.uploader)
    end

    before do
      stub_current_geo_node(secondary)
      old_upload.delete
      create(:upload, model: old_upload.model, uploader: old_upload.uploader, path: old_upload.path)
    end

    it 'keeps the file' do
      expect { described_class.new.perform('upload', old_upload.id) }
        .not_to change { File.exist?(file_path) }.from(true)
    end
  end

  include_examples 'an idempotent worker' do
    let!(:upload) { create(:upload) }
    let!(:registry) { create(:geo_upload_registry, file_id: upload.id) }
    let(:job_args) { ['upload', upload.id] }

    it 'calls replicator#replicate_destroy' do
      allow(Gitlab::Geo::Replicator).to receive(:for_replicable_params).and_return(replicator)

      expect(replicator).to receive(:replicate_destroy).exactly(IdempotentWorkerHelper::WORKER_EXEC_TIMES).times

      subject
    end

    # The service does other things, but don't test the service here.
    # This is only meant to show that the worker is idempotent.
    it 'deletes exactly one registry' do
      expect { subject }.to change { Geo::UploadRegistry.count }.by(-1)
    end
  end
end
