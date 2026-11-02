# frozen_string_literal: true

require "spec_helper"

RSpec.describe Geo::BlobDownloadService, feature_category: :geo_replication do
  include ::EE::GeoHelpers
  include ExclusiveLeaseHelpers

  let_it_be(:primary) { create(:geo_node, :primary) }
  let_it_be(:secondary) { create(:geo_node) }

  let(:model_record) { create(:package_file, :npm) }
  let(:replicator) { model_record.replicator }
  let(:registry_class) { replicator.registry_class }

  subject { described_class.new(replicator: replicator) }

  before do
    stub_current_geo_node(secondary)
  end

  describe "#execute" do
    let(:downloader) { double(:downloader) }

    context 'when the downloader result object contains an error' do
      let(:error) { StandardError.new('Error') }
      let(:result) do
        double(
          :result,
          success: false,
          primary_missing_file: false,
          bytes_downloaded: 0,
          reason: 'foo',
          extra_details: { error: error })
      end

      before do
        expect(downloader).to receive(:execute).and_return(result)
        expect(::Gitlab::Geo::Replication::BlobDownloader).to receive(:new).and_return(downloader)
      end

      it 'tracks exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          error,
          { model_record_id: model_record.id, replicable_name: 'package_file' }
        )

        subject.execute
      end

      it 'logs the result' do
        allow(Gitlab::Geo::Logger).to receive(:warn).with(
          hash_including(class: "Geo::PackageFileRegistry")
        )

        expect(Gitlab::Geo::Logger).to receive(:warn).with(
          {
            class: 'Geo::BlobDownloadService',
            message: 'Blob download',
            replicable_name: 'package_file',
            model_record_id: model_record.id,
            mark_as_synced: false,
            download_success: false,
            bytes_downloaded: 0,
            primary_missing_file: false,
            reason: 'foo',
            download_time_s: a_kind_of(Float),
            gitlab_host: a_kind_of(String),
            correlation_id: a_kind_of(String)
          }
        )

        subject.execute
      end
    end

    context 'when the replicator fails pre-download validation' do
      before do
        expect(replicator).to receive(:predownload_validation_failure).and_return(
          "This upload is busted"
        )
      end

      it "creates the registry" do
        expect do
          subject.execute
        end.to change { registry_class.count }.by(1)
      end

      it "sets sync state to failed" do
        subject.execute

        expect(registry_class.last).to be_failed
      end

      it "captures the error details in the registry record" do
        subject.execute
        expect(registry_class.last.last_sync_failure).to include("This upload is busted")
      end
    end

    context 'when exception is raised by the downloader' do
      let(:error) { StandardError.new('Some data inconsistency') }

      before do
        expect(downloader).to receive(:execute).and_raise(error)
        expect(::Gitlab::Geo::Replication::BlobDownloader).to receive(:new).and_return(downloader)
      end

      it 'does not raise error to Sidekiq job' do
        expect { subject.execute }.not_to raise_error
      end

      it 'returns false' do
        expect(subject.execute).to be false
      end

      it 'marks the replicator registry record as failed' do
        subject.execute

        registry = replicator.registry
        expect(registry).to be_failed
        expect(registry.last_sync_failure).to include("Error while attempting to sync")
      end

      it 'reports the exception' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          error,
          replicable_name: replicator.replicable_name,
          model_record_id: replicator.model_record_id
        )

        subject.execute
      end

      it 'logs the download failure' do
        allow(Gitlab::Geo::Logger).to receive(:warn).with(
          hash_including(class: "Geo::PackageFileRegistry")
        )

        expect(Gitlab::Geo::Logger).to receive(:warn).with(
          hash_including(
            class: 'Geo::BlobDownloadService',
            message: 'Blob download',
            mark_as_synced: false,
            download_success: false,
            bytes_downloaded: 0,
            primary_missing_file: false,
            replicable_name: replicator.replicable_name,
            model_record_id: replicator.model_record_id
          )
        )

        subject.execute
      end

      it 'logs with fallback values when download_result is nil' do
        allow(Gitlab::Geo::Logger).to receive(:warn).with(
          hash_including(class: "Geo::PackageFileRegistry")
        )

        expect(Gitlab::Geo::Logger).to receive(:warn).with(
          {
            class: 'Geo::BlobDownloadService',
            message: 'Blob download',
            replicable_name: 'package_file',
            model_record_id: model_record.id,
            mark_as_synced: false,
            download_success: false,
            bytes_downloaded: 0,
            primary_missing_file: false,
            download_time_s: a_kind_of(Float),
            reason: nil,
            gitlab_host: a_kind_of(String),
            correlation_id: a_kind_of(String)
          }
        )

        subject.execute
      end
    end

    context "when it can obtain the exclusive lease" do
      before do
        expect(downloader).to receive(:execute).and_return(result)
        expect(::Gitlab::Geo::Replication::BlobDownloader).to receive(:new).and_return(downloader)
      end

      context "when the registry record does not exist" do
        context "when the downloader returns success" do
          let(:result) { double(:result, success: true, primary_missing_file: false, bytes_downloaded: 123, reason: nil, extra_details: nil) }

          it "creates the registry" do
            expect do
              subject.execute
            end.to change { registry_class.count }.by(1)
          end

          it "sets sync state to synced" do
            subject.execute

            expect(registry_class.last).to be_synced
          end

          it 'logs the result' do
            expect(Gitlab::Geo::Logger).to receive(:warn).with(
              {
                class: 'Geo::BlobDownloadService',
                message: 'Blob download',
                replicable_name: 'package_file',
                model_record_id: model_record.id,
                mark_as_synced: true,
                download_success: true,
                bytes_downloaded: 123,
                primary_missing_file: false,
                reason: nil,
                download_time_s: a_kind_of(Float),
                gitlab_host: a_kind_of(String),
                correlation_id: a_kind_of(String)
              }
            )

            subject.execute
          end

          it "records the blob path" do
            subject.execute

            expect(registry_class.last.blob_path).to eq(replicator.deleted_params[:blob_path].to_s)
          end

          context "with an upload model" do
            let(:model_record) { create(:upload, :issuable_upload) }

            it "records the blob path and uploader class" do
              subject.execute

              expect(registry_class.last).to have_attributes(
                blob_path: replicator.deleted_params[:blob_path].to_s,
                uploader_class: replicator.deleted_params[:uploader_class]
              )
            end
          end

          context "when the blob path is over the limit" do
            before do
              allow(replicator).to receive(:deleted_params).and_return(
                model_record_id: model_record.id, uploader_class: "Foo", blob_path: "a" * 1025)
            end

            it "syncs without a blob path and logs a warning" do
              allow(Gitlab::Geo::Logger).to receive(:warn)
              expect(Gitlab::Geo::Logger).to receive(:warn).with(
                hash_including(
                  message: "Blob path too long to record",
                  replicable_name: "package_file",
                  model_record_id: model_record.id,
                  path_length: 1025
                )
              )

              subject.execute

              expect(registry_class.last).to be_synced
              expect(registry_class.last.blob_path).to be_nil
            end
          end

          context "when the registry has no blob_path column" do
            before do
              registry = replicator.registry
              allow(replicator).to receive(:registry).and_return(registry)
              allow(registry).to receive(:has_attribute?).and_call_original
              allow(registry).to receive(:has_attribute?).with(:blob_path).and_return(false)
              allow(registry).to receive(:blob_path=).and_raise(NoMethodError)
            end

            it "still syncs" do
              expect(subject.execute).to be true

              expect(registry_class.last).to be_synced
            end
          end

          context "when building the location raises" do
            let(:error) { StandardError.new("boom") }

            before do
              allow(replicator).to receive(:deleted_params).and_raise(error)
            end

            it "syncs without a blob path and tracks the exception" do
              expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
                error, replicable_name: "package_file", model_record_id: model_record.id)

              subject.execute

              expect(registry_class.last).to be_synced
              expect(registry_class.last.blob_path).to be_nil
            end

            context "with an upload model that has a location from an earlier sync" do
              let(:model_record) { create(:upload, :issuable_upload) }

              before do
                allow(Gitlab::ErrorTracking).to receive(:track_exception)
                replicator.registry.update!(blob_path: "old/path", uploader_class: "FileUploader")
              end

              it "clears the stored location" do
                subject.execute

                expect(registry_class.last).to be_synced
                expect(registry_class.last).to have_attributes(blob_path: nil, uploader_class: nil)
              end
            end
          end
        end

        context "when the downloader returns failure" do
          context "when the file is not missing on the primary" do
            let(:result) { double(:result, success: false, primary_missing_file: false, bytes_downloaded: 123, reason: "foo", extra_details: nil) }

            it "creates the registry" do
              expect do
                subject.execute
              end.to change { registry_class.count }.by(1)
            end

            it "sets sync state to failed" do
              subject.execute

              expect(registry_class.last).to be_failed
              expect(registry_class.last.blob_path).to be_nil
            end

            it 'caps retry wait time to 1 hour' do
              registry = replicator.registry
              registry.retry_count = 9999
              registry.save!

              subject.execute

              expect(registry.reload.retry_at).to be_within(10.minutes).of(1.hour.from_now)
            end
          end

          context "when the file is missing on the primary" do
            let(:result) { double(:result, success: false, primary_missing_file: true, bytes_downloaded: 123, reason: "foo", extra_details: nil) }

            it "creates the registry" do
              expect do
                subject.execute
              end.to change { registry_class.count }.by(1)
            end

            it "sets sync state to failed" do
              subject.execute

              expect(registry_class.last).to be_failed
            end

            it 'caps retry wait time to 4 hours' do
              registry = replicator.registry
              registry.retry_count = 9999
              registry.save!

              subject.execute

              expect(registry.reload.retry_at).to be_within(10.minutes).of(4.hours.from_now)
            end
          end
        end
      end
    end

    describe 'lease timeout' do
      it 'uses the configured sync_timeout for the exclusive lease' do
        allow(replicator.class).to receive(:sync_timeout).and_return(43210)

        expect_to_obtain_exclusive_lease(anything, timeout: 43210)

        subject.execute
      end
    end
  end
end
