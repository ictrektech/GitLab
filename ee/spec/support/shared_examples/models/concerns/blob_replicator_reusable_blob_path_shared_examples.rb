# frozen_string_literal: true

# Include in a blob replicator spec whose blob path is derived from record attributes that can be reused.
#
# Required let variables: model_record, record_reusing_path, record_with_other_path.
# Both records must be lazy so they are only created after model_record is deleted.
RSpec.shared_examples 'a blob replicator whose blob path can be reused' do
  let(:blob_path) { model_record.file.relative_path.to_s }
  let(:uploader_class) { model_record.file.class.to_s }

  describe '#blob_location_in_use?' do
    it 'is true while the record exists' do
      expect(replicator.blob_location_in_use?(blob_path, uploader_class)).to be(true)
    end

    it 'is false after the record is deleted' do
      model_record.delete

      expect(replicator.blob_location_in_use?(blob_path, uploader_class)).to be(false)
    end

    it 'is true when a new record reuses the path' do
      model_record.delete
      record_reusing_path

      expect(replicator.blob_location_in_use?(blob_path, uploader_class)).to be(true)
    end

    it 'is false when only a record with another path exists' do
      model_record.delete
      record_with_other_path

      expect(replicator.blob_location_in_use?(blob_path, uploader_class)).to be(false)
    end
  end

  describe '#replicate_destroy with a bucket prefix' do
    let(:model_record_id) { model_record.id }
    let(:bucket_prefix) { 'my/prefix' }
    let(:service) { instance_double(::Geo::FileRegistryRemovalService, execute: true) }
    let(:secondary_side_replicator) { replicator.class.new(model_record_id: model_record_id) }

    before do
      stub_current_geo_node(secondary)
      allow(uploader_class.constantize.object_store_options).to receive(:bucket_prefix).and_return(bucket_prefix)

      registry_class = replicator.class.registry_class
      create(
        registry_factory_name(registry_class),
        registry_class.model_foreign_key => model_record_id,
        blob_path: File.join(bucket_prefix, blob_path)
      )

      model_record.delete
    end

    it 'passes no location when a record reuses the path stored without the prefix' do
      record_reusing_path

      expect(::Geo::FileRegistryRemovalService)
        .to receive(:new)
        .with(secondary_side_replicator.replicable_name, model_record_id, nil, nil)
        .and_return(service)

      secondary_side_replicator.replicate_destroy({})
    end

    it 'removes the file using the stored location with the prefix when no record reuses the path' do
      expect(::Geo::FileRegistryRemovalService)
        .to receive(:new)
        .with(
          secondary_side_replicator.replicable_name,
          model_record_id,
          File.join(uploader_class.constantize.root, bucket_prefix, blob_path),
          uploader_class
        )
        .and_return(service)

      secondary_side_replicator.replicate_destroy({})
    end
  end
end
