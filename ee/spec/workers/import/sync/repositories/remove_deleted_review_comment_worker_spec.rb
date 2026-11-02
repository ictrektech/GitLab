# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::RemoveDeletedReviewCommentWorker, feature_category: :importers do
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      authority_state: :provider_canonical,
      project: create(:project, :import_finished)
    )
  end

  let(:lease_context) { instance_double(Import::Sync::Repositories::ApplicationLease::Context) }
  let(:remover) do
    instance_double(Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService, remove_comment: nil)
  end

  subject(:worker) { described_class.new }

  before do
    lease = instance_double(Import::Sync::Repositories::ApplicationLease)
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).with(repository.id).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
    allow(Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService).to receive(:new)
      .with(repository, lease_context: lease_context)
      .and_return(remover)
  end

  it 'removes the review comment under the repository lease' do
    worker.perform(repository.id, 402)

    expect(remover).to have_received(:remove_comment).with(402)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [repository.id, 402] }
  end

  it 'defers on the table it writes' do
    expect(described_class.database_health_check_attrs).to include(gitlab_schema: :gitlab_main_org, tables: [:notes])
  end

  it 'shares the GitHub import concurrency limit' do
    stub_application_setting(import_jobs_concurrency_limit: 7)

    expect(described_class.get_concurrency_limit).to eq(7)
  end

  it 'does nothing after the repository is removed' do
    worker.perform(non_existing_record_id, 402)

    expect(remover).not_to have_received(:remove_comment)
  end

  context 'when GitHub updates are not active' do
    let(:repository) { create(:import_sync_repository, :oauth, authority_state: :gitlab_canonical) }

    it 'does nothing' do
      worker.perform(repository.id, 402)

      expect(remover).not_to have_received(:remove_comment)
    end
  end

  context 'when the import did not finish' do
    let(:repository) do
      create(
        :import_sync_repository,
        :oauth,
        authority_state: :provider_canonical,
        project: create(:project, :import_failed)
      )
    end

    it 'does nothing' do
      worker.perform(repository.id, 402)

      expect(remover).not_to have_received(:remove_comment)
    end
  end
end
