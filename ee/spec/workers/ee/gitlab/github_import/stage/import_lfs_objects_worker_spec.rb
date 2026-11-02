# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Stage::ImportLfsObjectsWorker, feature_category: :importers do
  let_it_be_with_reload(:project) { create(:project) }

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:waiter) { Gitlab::JobWaiter.new(2, '123') }

  subject(:worker) { described_class.new }

  before do
    allow_next_instance_of(Gitlab::GithubImport::Importer::LfsObjectsImporter) do |importer|
      allow(importer).to receive(:execute).and_return(waiter)
    end
  end

  describe '#import' do
    context 'when continuous sync is selected' do
      before do
        Gitlab::GithubImport::Settings.new(project).write(optional_stages: { continuous_sync: true })
      end

      it 'advances to the continuous_sync stage' do
        expect(Gitlab::GithubImport::AdvanceStageWorker)
          .to receive(:perform_async)
          .with(project.id, { '123' => 2 }, 'continuous_sync')

        worker.import(client, project)
      end
    end

    context 'when continuous sync is not selected' do
      before do
        Gitlab::GithubImport::Settings.new(project).write(optional_stages: { continuous_sync: false })
      end

      it 'advances to the finish stage' do
        expect(Gitlab::GithubImport::AdvanceStageWorker)
          .to receive(:perform_async)
          .with(project.id, { '123' => 2 }, 'finish')

        worker.import(client, project)
      end
    end
  end
end
