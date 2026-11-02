# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::RestoreDiffCommitsWorker, feature_category: :code_review_workflow do
  describe '#perform' do
    let(:job_args) { [non_existing_record_id] }

    subject(:perform) { described_class.new.perform(*job_args) }

    it_behaves_like 'an idempotent worker'

    it 'does nothing' do
      expect(MergeRequestDiff).not_to receive(:find_by_id)

      expect(perform).to be_nil
    end
  end
end
