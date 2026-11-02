# frozen_string_literal: true

# Include in a blob replicator's 'deleted event consumption' block.
#
# Required let variables: model_record, model_record_id, blob_path, uploader_class,
# deleted_params, secondary_blob_path.
RSpec.shared_examples 'a blob replicator that removes its blob using the stored location' do
  let(:stored_blob_path) { blob_path }
  let(:service) { instance_double(::Geo::FileRegistryRemovalService, execute: true) }
  let(:secondary_side_replicator) { replicator.class.new(model_record_id: model_record_id) }

  def create_registry_with_location(path)
    registry_class = replicator.class.registry_class
    attributes = {
      registry_class.model_foreign_key => model_record_id,
      blob_path: path,
      uploader_class: uploader_class
    }.select { |key, _| registry_class.new.has_attribute?(key) }

    create(registry_factory_name(registry_class), attributes)
  end

  def expect_removal_service_with(blob_path, uploader_class)
    expect(::Geo::FileRegistryRemovalService)
      .to receive(:new)
      .with(secondary_side_replicator.replicable_name, model_record_id, blob_path, uploader_class)
      .and_return(service)
  end

  before do
    create_registry_with_location(stored_blob_path)
  end

  context 'when the model record still exists' do
    it 'passes no location so the service builds it from the model' do
      expect_removal_service_with(nil, nil)

      secondary_side_replicator.replicate_destroy({})
    end
  end

  context 'when the model record is gone' do
    before do
      model_record.delete
    end

    it 'removes the file using the stored location when there is no event data' do
      expect_removal_service_with(secondary_blob_path, uploader_class)

      secondary_side_replicator.replicate_destroy({})
    end

    context 'when the event data has a location' do
      let(:stored_blob_path) { 'other/path' }

      it 'prefers the event location' do
        expect_removal_service_with(secondary_blob_path, uploader_class)

        secondary_side_replicator.replicate_destroy(deleted_params)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(geo_blob_removal_uses_registry_location: false)
      end

      it 'does not use the stored location' do
        expect_removal_service_with(nil, nil)

        secondary_side_replicator.replicate_destroy({})
      end
    end

    context 'when no location is stored' do
      let(:stored_blob_path) { nil }

      it 'passes no location' do
        expect_removal_service_with(nil, nil)

        secondary_side_replicator.replicate_destroy({})
      end
    end

    context 'when the stored uploader class is blank' do
      before do
        allow(secondary_side_replicator).to receive(:stored_uploader_class).and_return(nil)
      end

      it 'passes no location' do
        expect_removal_service_with(nil, nil)

        secondary_side_replicator.replicate_destroy({})
      end
    end

    context 'when a live record still uses the stored location' do
      before do
        allow(secondary_side_replicator).to receive(:blob_location_in_use?).and_return(true)
      end

      it 'passes no location' do
        expect_removal_service_with(nil, nil)

        secondary_side_replicator.replicate_destroy({})
      end
    end
  end
end
