# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::UpdateWorker, feature_category: :security_asset_inventories do
  let(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [[non_existing_record_id]] }
  end

  describe '#perform' do
    let(:project_ids) { [1, 2, 3] }

    before do
      allow(Security::TriageCoverage::RecomputeService).to receive(:execute)
    end

    it 'calls RecomputeService with the given project ids' do
      worker.perform(project_ids)

      expect(Security::TriageCoverage::RecomputeService).to have_received(:execute).with(project_ids)
    end

    context 'when project_ids is empty' do
      let(:project_ids) { [] }

      it 'does not call RecomputeService' do
        worker.perform(project_ids)

        expect(Security::TriageCoverage::RecomputeService).not_to have_received(:execute)
      end
    end

    context 'when project_ids is nil' do
      let(:project_ids) { nil }

      it 'does not call RecomputeService' do
        worker.perform(project_ids)

        expect(Security::TriageCoverage::RecomputeService).not_to have_received(:execute)
      end
    end
  end
end
