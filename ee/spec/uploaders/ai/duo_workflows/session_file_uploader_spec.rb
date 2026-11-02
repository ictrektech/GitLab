# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionFileUploader, feature_category: :duo_agent_platform do
  let_it_be(:session_file) { create(:duo_workflows_session_file) }

  subject(:uploader) { described_class.new(session_file, :file) }

  describe '.workhorse_local_upload_path' do
    it 'returns path that includes uploads dir' do
      expect(described_class.workhorse_local_upload_path).to end_with('/uploads/tmp/uploads')
    end
  end

  describe '.default_store' do
    it 'is local when object storage is disabled' do
      expect(described_class.default_store).to eq(ObjectStorage::Store::LOCAL)
    end

    it 'is remote when object storage is enabled' do
      stub_uploads_object_storage(described_class)

      expect(described_class.default_store).to eq(ObjectStorage::Store::REMOTE)
    end
  end

  describe '#store_dir' do
    it 'is scoped to the record id' do
      expect(uploader.store_dir).to end_with("ai/duo_workflows/session_file/file/#{session_file.id}")
    end
  end
end
