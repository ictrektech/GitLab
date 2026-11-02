# frozen_string_literal: true

RSpec.shared_context 'with a successful blob download' do
  before do
    model_record.save! if model_record.new_record?
    stub_current_geo_node(secondary)
    allow(replicator).to receive(:in_replicables_for_current_secondary?).and_return(true)
    allow_next_instance_of(::Gitlab::Geo::Replication::BlobDownloader) do |downloader|
      allow(downloader).to receive(:execute).and_return(
        ::Gitlab::Geo::Replication::BlobDownloader::Result.new(success: true, bytes_downloaded: 1))
    end
  end
end

RSpec.shared_examples 'a blob replicator that records its blob location' do
  describe '#sync' do
    context 'when in replicables for current secondary' do
      include_context 'with a successful blob download'

      it 'records the blob path on the registry' do
        replicator.sync

        expect(replicator.registry.reload.blob_path).to eq(replicator.deleted_params[:blob_path].to_s)
      end
    end
  end
end
