# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::UserUploadReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:geo_user_upload) }

  include_examples 'a blob replicator with a read-only replicable model'
  include_examples 'a blob replicator with upload replicator behavior'

  describe '#deleted_params with a bucket prefix' do
    let(:model_record) { create(:geo_user_upload, :remote_store) }
    let(:uploader_class) { model_record.uploader.constantize }
    let(:bucket_prefix) { 'my/prefix' }

    before do
      stub_uploads_object_storage(uploader_class)
      allow(uploader_class.object_store_options).to receive(:bucket_prefix).and_return(bucket_prefix)
    end

    it 'includes the prefix in the blob path of an object storage upload' do
      expect(replicator.deleted_params[:blob_path]).to start_with("#{bucket_prefix}/")
    end
  end

  describe '#replicate_destroy with a bucket prefix' do
    let(:uploader_class) { model_record.uploader }
    let(:model_record_id) { model_record.id }
    let(:local_path) { model_record.path }
    let(:bucket_prefix) { 'my/prefix' }
    let(:stored_blob_path) { File.join(bucket_prefix, local_path) }
    let(:service) { instance_double(::Geo::FileRegistryRemovalService, execute: true) }
    let(:secondary_side_replicator) { described_class.new(model_record_id: model_record_id) }

    before do
      stub_current_geo_node(secondary)
      allow(uploader_class.constantize.object_store_options).to receive(:bucket_prefix).and_return(bucket_prefix)

      create(
        :geo_user_upload_registry,
        user_upload_id: model_record_id,
        blob_path: stored_blob_path,
        uploader_class: uploader_class
      )

      model_record.delete
    end

    def expect_removal_service_with(blob_path, uploader_class)
      expect(::Geo::FileRegistryRemovalService)
        .to receive(:new)
        .with(secondary_side_replicator.replicable_name, model_record_id, blob_path, uploader_class)
        .and_return(service)
    end

    it 'passes no location when an upload reuses the path stored without the prefix' do
      create(:upload, model: model_record.model, path: local_path)

      expect_removal_service_with(nil, nil)

      secondary_side_replicator.replicate_destroy({})
    end

    it 'removes the file using the stored location with the prefix when no upload reuses the path' do
      expect_removal_service_with(File.join(uploader_class.constantize.root, stored_blob_path), uploader_class)

      secondary_side_replicator.replicate_destroy({})
    end

    context 'when a local path starts with the prefix' do
      let(:bucket_prefix) { 'uploads' }
      let(:stored_blob_path) { local_path }

      it 'passes no location when an upload reuses the stored path' do
        expect(local_path).to start_with("#{bucket_prefix}/")

        create(:upload, model: model_record.model, path: local_path)

        expect_removal_service_with(nil, nil)

        secondary_side_replicator.replicate_destroy({})
      end
    end
  end
end
