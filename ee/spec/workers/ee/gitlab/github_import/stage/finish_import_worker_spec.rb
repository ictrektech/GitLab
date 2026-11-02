# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Stage::FinishImportWorker, feature_category: :importers do
  let_it_be_with_reload(:project) { create(:project, :import_started) }

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:reference_store_pending) { false }

  subject(:worker) { described_class.new }

  before do
    allow(project).to receive(:after_import) { project.import_state.update!(status: :finished) }
    allow(worker).to receive_messages(reference_store_pending?: reference_store_pending, report_import_time: nil)
    allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
  end

  describe '#import' do
    context 'when the sync repository is provider canonical' do
      let!(:sync_repository) do
        create(:import_sync_repository, :oauth, project: project, authority_state: :provider_canonical)
      end

      it 'enqueues the first reconcile with the current application generation once the import finished' do
        worker.import(client, project)

        expect(Import::Sync::Repositories::ReconcileWorker)
          .to have_received(:perform_async).with(sync_repository.id, sync_repository.application_generation).once
      end

      context 'when the finish stage waits for placeholder references' do
        let(:reference_store_pending) { true }

        before do
          allow(described_class).to receive(:perform_in)
        end

        it 'does not enqueue the reconcile while the import is still running' do
          worker.import(client, project)

          expect(described_class).to have_received(:perform_in).with(30.seconds, project.id)
          expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
        end
      end
    end

    context 'when the sync repository is not provider canonical' do
      where(:authority_state) { [[:provisioning], [:bootstrap_canceled], [:gitlab_canonical]] }

      with_them do
        before do
          create(:import_sync_repository, :oauth, project: project, authority_state: authority_state)
        end

        it 'does not enqueue the reconcile' do
          worker.import(client, project)

          expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
        end
      end
    end

    context 'when the project has no sync repository' do
      it 'does not enqueue the reconcile' do
        worker.import(client, project)

        expect(Import::Sync::Repositories::ReconcileWorker).not_to have_received(:perform_async)
      end
    end
  end
end
