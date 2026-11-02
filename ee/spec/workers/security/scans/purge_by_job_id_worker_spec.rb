# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Scans::PurgeByJobIdWorker, feature_category: :vulnerability_management do
  let(:job_ids) { [1, 2, 3] }
  let(:event) { Ci::JobArtifactsDeletedEvent.new(data: { job_ids: job_ids }) }

  subject { consume_event(subscriber: described_class, event: event) }

  before do
    allow(::Security::PurgeScansService).to receive(:purge_by_build_ids)
  end

  it_behaves_like 'subscribes to event'

  it 'has the correct concurrency limit' do
    expect(described_class.get_concurrency_limit).to eq(25)
  end

  it 'initiates the cleanup by build ids' do
    subject

    expect(::Security::PurgeScansService).to have_received(:purge_by_build_ids).with(job_ids)
  end

  context 'when the event contains duplicate job ids' do
    let(:job_ids) { [1, 2, 2, 3, 1] }

    it 'initiates the cleanup with unique build ids' do
      subject

      expect(::Security::PurgeScansService).to have_received(:purge_by_build_ids).with([1, 2, 3])
    end
  end
end
