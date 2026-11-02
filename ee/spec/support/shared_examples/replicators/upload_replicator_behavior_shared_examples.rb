# frozen_string_literal: true

# Include one of these shared examples in specs of Replicators that include
# Geo::Concerns::UploadReplicatorBehavior:
#
# - 'a blob replicator for upload records': Geo::UploadReplicator.
# - 'a blob replicator with upload replicator behavior': upload partition
#   Replicators, which also adopt the parent Upload's checksum. It includes
#   'a blob replicator for upload records'.
#
# Required let variables:
#
# - model_record: A valid, persisted instance of Upload or of an upload
#                 partition model class (e.g. Geo::AbuseReportUpload).
#
RSpec.shared_examples 'a blob replicator for upload records' do
  let(:upload_fixture_file_checksum) { 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }
  let(:remote_file_size_checksum) { '065112' }

  shared_context "with remotely stored upload" do
    before do
      file_double = instance_double(CarrierWave::SanitizedFile, exists?: true, size: 65112)
      uploader = replicator.carrierwave_uploader
      allow(uploader).to receive_messages(file_storage?: false, file: file_double)
      allow(replicator).to receive(:carrierwave_uploader).and_return(uploader)
    end
  end

  describe '#sync' do
    context 'when in replicables for current secondary' do
      include_context 'with a successful blob download'

      it 'records the uploader class on the registry' do
        replicator.sync

        expect(replicator.registry.reload.uploader_class).to eq(replicator.deleted_params[:uploader_class])
      end
    end
  end

  describe "#predownload_validation_failure" do
    context "when upload is valid and has an associated model/owner" do
      it "returns nil" do
        expect(replicator.predownload_validation_failure).to be_nil
      end
    end

    context "when upload is orphaned from its own model association" do
      let(:expected_error_message) do
        "The model which owns this #{replicator.replicable_name} is missing. " \
          "#{replicator.replicable_name} ID##{model_record.id}, " \
          "#{model_record.model_type} ID##{model_record.model_id}"
      end

      before do
        # break the model association on the upload
        model_record.model_id = -1
        model_record.save!(validate: false)
        model_record.reload
      end

      it "returns an error string" do
        expect(replicator.predownload_validation_failure).to eq(expected_error_message)
      end
    end
  end

  describe "#calculate_checksum override" do
    context "when upload has an associated model/owner" do
      it "returns the upload file checksum" do
        expect(replicator.calculate_checksum).to eq(upload_fixture_file_checksum)
      end

      context "when the file is remotely stored" do
        include_context "with remotely stored upload"

        it "returns the file size as checksum" do
          expect(replicator.calculate_checksum).to eq(remote_file_size_checksum)
        end
      end
    end

    context "when upload is orphaned from its own model association" do
      let(:expected_error_message) do
        "The model which owns this #{replicator.replicable_name} is missing. " \
          "#{replicator.replicable_name} ID##{model_record.id}, " \
          "#{model_record.model_type} ID##{model_record.model_id}"
      end

      before do
        # break the model association on the upload
        model_record.model_id = -1
        model_record.save!(validate: false)
        model_record.reload
      end

      it "raises a clearer error" do
        expect { replicator.calculate_checksum }.to raise_error(expected_error_message)
      end
    end
  end

  describe '#blob_location_in_use?' do
    it 'is true when an upload row has the same uploader and path' do
      expect(replicator.blob_location_in_use?(model_record.path, model_record.uploader)).to be(true)
    end

    it 'is false when no upload row has that path' do
      expect(replicator.blob_location_in_use?('no/such/path', model_record.uploader)).to be(false)
    end

    it 'is false when the path belongs to a different uploader' do
      expect(replicator.blob_location_in_use?(model_record.path, 'OtherUploader')).to be(false)
    end
  end

  describe "#model_is_missing_error_message" do
    context "when upload has an associated model/owner" do
      it "returns nil" do
        expect(replicator.model_is_missing_error_message).to be_nil
      end
    end

    context "when upload is orphaned from its own model association" do
      let(:expected_error_message) do
        "The model which owns this #{replicator.replicable_name} is missing. " \
          "#{replicator.replicable_name} ID##{model_record.id}, " \
          "#{model_record.model_type} ID##{model_record.model_id}"
      end

      before do
        # break the model association on the upload
        model_record.model_id = -1
        model_record.save!(validate: false)
        model_record.reload
      end

      it "returns an error message" do
        expect(replicator.model_is_missing_error_message).to eq(expected_error_message)
      end
    end
  end
end

RSpec.shared_examples 'a blob replicator with upload replicator behavior' do
  include_examples 'a blob replicator for upload records'

  describe '.replicable_group' do
    it 'groups the replicator under uploads' do
      expect(described_class.replicable_group).to eq('uploads')
      expect(described_class.replicable_group_title).to eq(s_('Geo|Uploads'))
      expect(described_class.replicable_group_description)
        .to eq(s_('Geo|Uploads are replicated by type. Select a type to review its replication status.'))
    end
  end

  describe "#calculate_checksum override" do
    context "when the parent upload_state has not been verified yet" do
      it "falls back to the file-based checksum calculation" do
        # upload_state is pending by default
        expect(replicator.calculate_checksum).to eq(upload_fixture_file_checksum)
      end

      context "when the file is remotely stored" do
        include_context "with remotely stored upload"

        it "falls back to the object storage checksum calculation" do
          expect(replicator).not_to receive(:sha256_hexdigest)
          expect(replicator.calculate_checksum).to eq(remote_file_size_checksum)
        end
      end
    end

    context "when the parent upload_state verification has failed" do
      before do
        model_record.upload_state.update!(
          verification_state: model_record.class.verification_state_value(:verification_failed),
          verification_failure: 'Could not calculate the checksum'
        )
        model_record.reload
      end

      it "falls back to the file-based checksum calculation" do
        expect(replicator.calculate_checksum).to eq(upload_fixture_file_checksum)
      end

      context "when the file is remotely stored" do
        include_context "with remotely stored upload"

        it "falls back to the object storage checksum calculation" do
          expect(replicator).not_to receive(:sha256_hexdigest)
          expect(replicator.calculate_checksum).to eq(remote_file_size_checksum)
        end
      end
    end

    context "when the parent upload_state has been verified successfully" do
      let(:parent_checksum) { 'abc123def456abc123def456abc123def456abc123def456abc123def456abc1' }

      before do
        model_record.upload_state.update!(
          verification_state: model_record.class.verification_state_value(:verification_succeeded),
          verification_checksum: parent_checksum
        )
        model_record.reload
      end

      it "adopts the parent checksum without reading the file" do
        expect(model_record).not_to receive(:sha256_hexdigest)
        expect(replicator.calculate_checksum).to eq(parent_checksum)
      end

      context "when the file is remotely stored" do
        include_context "with remotely stored upload"

        it "adopts the parent checksum without calling format_file_size_for_checksum" do
          expect(replicator).not_to receive(:format_file_size_for_checksum)
          expect(replicator.calculate_checksum).to eq(parent_checksum)
        end
      end

      context "when this site has already verified the replicable" do
        before do
          model_record.verification_state_object.update!(verified_at: 1.day.ago)
        end

        it "reads the file" do
          expect(replicator.calculate_checksum).to eq(upload_fixture_file_checksum)
        end
      end
    end
  end

  describe "#parent_upload_verification_succeeded?" do
    context "when the parent upload_state is nil" do
      before do
        allow(model_record).to receive(:upload_state).and_return(nil)
      end

      it "returns false" do
        expect(replicator.parent_upload_verification_succeeded?).to be(false)
      end
    end

    context "when the parent upload_state has not been verified yet" do
      it "returns false" do
        expect(replicator.parent_upload_verification_succeeded?).to be(false)
      end
    end

    context "when the parent upload_state verification has failed" do
      before do
        model_record.upload_state.update!(
          verification_state: model_record.class.verification_state_value(:verification_failed),
          verification_failure: 'Could not calculate the checksum'
        )
        model_record.reload
      end

      it "returns false" do
        expect(replicator.parent_upload_verification_succeeded?).to be(false)
      end
    end

    context "when the parent upload_state has been verified successfully" do
      before do
        model_record.upload_state.update!(
          verification_state: model_record.class.verification_state_value(:verification_succeeded),
          verification_checksum: 'abc123'
        )
        model_record.reload
      end

      it "returns true" do
        expect(replicator.parent_upload_verification_succeeded?).to be(true)
      end

      context "when this site has already verified the replicable" do
        before do
          model_record.verification_state_object.update!(verified_at: 1.day.ago)
        end

        it "returns false so reverification reads the file" do
          expect(replicator.parent_upload_verification_succeeded?).to be(false)
        end
      end

      context "on a Geo secondary" do
        before do
          stub_secondary_site
        end

        context "when the registry has not been verified yet" do
          it "returns true" do
            expect(replicator.parent_upload_verification_succeeded?).to be(true)
          end
        end

        context "when the registry has already been verified" do
          before do
            replicator.registry.update!(verified_at: 1.day.ago)
          end

          it "returns false so reverification reads the file" do
            expect(replicator.parent_upload_verification_succeeded?).to be(false)
          end
        end
      end

      context "when the replicable is mutable" do
        before do
          allow(replicator).to receive(:immutable?).and_return(false)
        end

        it "returns false to avoid serving a potentially stale checksum" do
          expect(replicator.parent_upload_verification_succeeded?).to be(false)
        end
      end
    end
  end

  describe "#ok_to_skip_download?" do
    subject(:ok_to_skip_download?) { replicator.ok_to_skip_download? }

    before do
      stub_secondary_site
      allow(replicator).to receive(:resource_exists?).and_return(true)
      allow(model_record).to receive(:in_verifiables?).and_return(true)
    end

    context "when the parent upload_state has not been verified" do
      it { is_expected.to be(true) }
    end

    context "when the parent upload_state has been verified" do
      before do
        model_record.upload_state.update!(
          verification_state: model_record.class.verification_state_value(:verification_succeeded),
          verification_checksum: 'abc123'
        )
        model_record.reload
      end

      context "when the legacy registry verified this site's copy" do
        before do
          create(:geo_upload_registry, :verification_succeeded, upload: Upload.find(model_record.id))
        end

        it { is_expected.to be(true) }
      end

      context "when the legacy registry failed verification" do
        before do
          create(:geo_upload_registry, :verification_failed, upload: Upload.find(model_record.id))
        end

        it { is_expected.to be(false) }
      end

      context "when there is no legacy registry" do
        it { is_expected.to be(false) }
      end
    end
  end
end
