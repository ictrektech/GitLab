# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::UploadReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:upload, :with_file) }

  include_examples 'a blob replicator'
  include_examples 'a blob replicator for upload records'

  describe '.replicable_group' do
    it 'is not grouped, since its model is Upload itself' do
      expect(described_class.replicable_group).to be_nil
      expect(described_class.replicable_group_title).to be_nil
      expect(described_class.replicable_group_description).to be_nil
    end
  end

  describe '#event_params' do
    it 'includes model_type so LogCursor can prune partitioned table lookups' do
      replicator = described_class.new(model_record: model_record)

      expect(replicator.event_params).to include('model_type' => model_record.model_type)
    end
  end

  context 'when the primary has verified the upload' do
    let(:file_path) { replicator.carrierwave_uploader.path }

    before do
      model_record.upload_state.update!(
        verification_state: Upload.verification_state_value(:verification_succeeded),
        verification_checksum: Digest::SHA256.file(file_path).hexdigest
      )
      model_record.reload
    end

    describe '#calculate_checksum' do
      before do
        File.write(file_path, 'changed')
      end

      it 'reads the file instead of adopting the upload_state checksum' do
        expect(replicator.calculate_checksum).to eq(Digest::SHA256.hexdigest('changed'))
      end

      context 'on a Geo secondary' do
        before do
          stub_secondary_site
        end

        it 'reads the file instead of adopting the primary checksum' do
          expect(replicator.calculate_checksum).to eq(Digest::SHA256.hexdigest('changed'))
        end
      end
    end

    context 'on a Geo secondary' do
      before do
        stub_secondary_site
      end

      describe '#verify' do
        let(:damaged_content) { 'damaged on the secondary' }
        let(:checksum_mismatch_attributes) do
          {
            verification_failed?: true,
            checksum_mismatch: true,
            verification_checksum: Digest::SHA256.hexdigest(damaged_content)
          }
        end

        before do
          File.write(file_path, damaged_content)
        end

        it 'fails the first verification of a damaged file with a checksum mismatch' do
          registry = create(:geo_upload_registry, :synced, upload: model_record)

          replicator.verify

          expect(registry.reload).to have_attributes(checksum_mismatch_attributes)
        end

        it 'fails the reverification of a damaged file with a checksum mismatch' do
          registry = create(:geo_upload_registry, :verification_succeeded, upload: model_record)
          registry.verification_pending!

          replicator.verify

          expect(registry.reload).to have_attributes(checksum_mismatch_attributes)
        end
      end

      describe '#ok_to_skip_download?' do
        it 'skips the download of a file that already exists' do
          create(:geo_upload_registry, upload: model_record)

          expect(replicator.ok_to_skip_download?).to be(true)
        end
      end
    end
  end
end
