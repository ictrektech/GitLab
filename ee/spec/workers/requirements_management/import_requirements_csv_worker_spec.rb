# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RequirementsManagement::ImportRequirementsCsvWorker, feature_category: :requirements_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, reporter_of: project) }

  let(:upload) { create(:upload, :with_file) }

  before do
    stub_licensed_features(requirements: true)
  end

  subject { described_class.new.perform(user.id, project.id, upload.id) }

  describe '#perform' do
    it 'calls #execute on Requirements::ImportCsvService and destroys upload' do
      expect_next_instance_of(RequirementsManagement::ImportCsvService) do |instance|
        expect(instance).to receive(:execute).and_return({ success: 5, error_lines: [], parse_error: false })
      end

      subject

      expect { upload.reload }.to raise_error ActiveRecord::RecordNotFound
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [user.id, project.id, upload.id] }
    end

    shared_examples 'skips the import' do
      it 'does not call the import service and does not raise' do
        expect(RequirementsManagement::ImportCsvService).not_to receive(:new)

        expect { described_class.new.perform(*job_args) }.not_to raise_error
      end
    end

    context 'when the upload does not exist' do
      let(:job_args) { [user.id, project.id, non_existing_record_id] }

      it_behaves_like 'skips the import'
    end

    context 'when the user does not exist' do
      let(:job_args) { [non_existing_record_id, project.id, upload.id] }

      it_behaves_like 'skips the import'

      it 'does not destroy the upload' do
        described_class.new.perform(*job_args)

        expect(Upload.exists?(upload.id)).to be(true)
      end
    end

    context 'when the project does not exist' do
      let(:job_args) { [user.id, non_existing_record_id, upload.id] }

      it_behaves_like 'skips the import'

      it 'does not destroy the upload' do
        described_class.new.perform(*job_args)

        expect(Upload.exists?(upload.id)).to be(true)
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    it 'destroys the upload' do
      job = { 'args' => [user.id, project.id, upload.id] }

      expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new) }
        .to change { Upload.exists?(upload.id) }.from(true).to(false)
    end

    it 'does not raise when the upload does not exist' do
      job = { 'args' => [user.id, project.id, non_existing_record_id] }

      expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new) }.not_to raise_error
    end
  end
end
