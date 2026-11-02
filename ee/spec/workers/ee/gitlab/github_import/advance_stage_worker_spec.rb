# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::AdvanceStageWorker, feature_category: :importers do
  let_it_be(:project) { create(:project, import_status: :started, import_jid: '123') }

  subject(:worker) { described_class.new }

  describe '#perform' do
    context 'when the next stage is continuous_sync' do
      it 'enqueues EnableContinuousSyncWorker' do
        expect(Gitlab::GithubImport::Stage::EnableContinuousSyncWorker)
          .to receive(:perform_async).with(project.id)
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).not_to receive(:perform_async)

        worker.perform(project.id, {}, 'continuous_sync')
      end
    end

    context 'when the next stage is a CE stage' do
      it 'enqueues the worker from STAGES' do
        expect(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async).with(project.id)
        expect(Gitlab::GithubImport::Stage::EnableContinuousSyncWorker).not_to receive(:perform_async)

        worker.perform(project.id, {}, 'finish')
      end
    end
  end
end
