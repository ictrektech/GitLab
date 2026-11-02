# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ScheduleRepairWorker, feature_category: :importers do
  let(:repository) { create(:import_sync_repository, :oauth, authority_state: :provider_canonical) }
  let(:service) { instance_double(Import::Sync::Repositories::RequestUpdateService, execute: 0) }

  subject(:worker) { described_class.new }

  before do
    allow(Import::Sync::Repositories::RequestUpdateService).to receive(:new).and_return(service)
  end

  it 'defers on the table it writes' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org,
      tables: [:import_sync_repository_states]
    )
  end

  it 'shares the GitHub import concurrency limit' do
    stub_application_setting(import_jobs_concurrency_limit: 7)

    expect(described_class.get_concurrency_limit).to eq(7)
  end

  it 'uses the shared repository update path for data repair without recording a provider event' do
    worker.perform(repository.id)

    expect(Import::Sync::Repositories::RequestUpdateService)
      .to have_received(:new).with(repository, event_at: nil)
    expect(service).to have_received(:execute)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [repository.id] }
  end

  it 'logs and swallows an inactive authority' do
    allow(service).to receive(:execute).and_raise(Import::Sync::Errors::InactiveAuthorityError)
    expect(Gitlab::GithubImport::Logger).to receive(:info).with(
      message: 'skipping scheduled repair, GitHub updates are not active',
      import_sync_repository_id: repository.id
    )

    expect { worker.perform(repository.id) }.not_to raise_error
  end

  it 'does nothing after the repository is removed' do
    worker.perform(non_existing_record_id)

    expect(Import::Sync::Repositories::RequestUpdateService).not_to have_received(:new)
  end

  it 'runs regardless of the import-time flag' do
    stub_feature_flags(github_continuous_import: false)

    worker.perform(repository.id)

    expect(service).to have_received(:execute)
  end
end
