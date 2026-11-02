# frozen_string_literal: true

require 'spec_helper'

# The whole stop from the request to the cleanup, with only the reconcile services and the GitHub call replaced.
# It proves the pieces fit together; each piece has its own spec for the details.
RSpec.describe Import::Sync::Repositories::RequestStopService, 'stop flow',
  :sidekiq_inline, :clean_gitlab_redis_shared_state, feature_category: :importers do
  let_it_be_with_reload(:project) do
    create(:project, :import_finished, import_type: 'github', import_url: 'https://github.com/octocat/hello-world.git')
  end

  let(:application_generation) { 4 }
  let(:requested_at) { Time.zone.parse('2026-08-25 14:00:00') }
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: project,
      authority_state: :provider_canonical,
      application_generation: application_generation,
      provider_webhook_xid: 42,
      webhook_secret: 'webhook-secret'
    )
  end

  let!(:domain_states) do
    Import::Sync::RepositoryState.domains.keys.index_with do |domain|
      create(:import_sync_repository_state, repository: repository, domain: domain)
    end
  end

  let(:calls) { [] }
  let(:authority_seen_by_final_pass) { [] }
  let(:source_service) { instance_double(Import::Sync::Repositories::ReconcileSourceService) }
  let(:work_items_service) { instance_double(Import::Sync::Repositories::ReconcileWorkItemsService) }

  # Records the removal as the real DELETE, so the order check does not depend on how the project is loaded.
  let!(:removal_subscriber) do
    ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      calls << [:remove_import_data] if payload[:sql].start_with?('DELETE FROM "project_import_data"')
    end
  end

  subject(:service) { described_class.new(repository, requested_at: requested_at) }

  before do
    project.build_or_assign_import_data(credentials: { user: 'token' }).save!

    allow(Gitlab::GithubImport::Logger).to receive(:info)
    allow(Gitlab::GithubImport).to receive(:new_client_for).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do |client|
        allow(client).to receive(:delete_hook) do |repository_xid, hook_xid|
          calls << [:delete_hook, repository_xid, hook_xid]
        end
      end
    end

    allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new).and_return(source_service)
    allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new).and_return(work_items_service)
    allow(source_service).to receive(:execute) { final_pass(%w[inventory source]) }
    allow(work_items_service).to receive(:execute) { final_pass(%w[work_items]) }
  end

  after do
    ActiveSupport::Notifications.unsubscribe(removal_subscriber)
  end

  # Stands in for a successful provider pass: records the authority it ran under and makes the domains current.
  def final_pass(domains)
    authority_seen_by_final_pass << Import::Sync::Repository.find(repository.id).authority_state
    repository.sync_states.where(domain: domains).find_each do |state|
      state.update!(synced_generation: state.desired_generation, state: :current)
    end

    { applied_domains: domains, follow_up: false }
  end

  it 'takes a provider_canonical row to gitlab_canonical, deletes the hook, then removes the import data #security' do
    expect(project.reload.import_data).to be_present

    expect(service.execute).to eq(application_generation + 1)

    expect(authority_seen_by_final_pass).to eq(%w[cutting_over cutting_over])
    expect(repository.reload).to have_attributes(
      authority_state: 'gitlab_canonical',
      application_generation: application_generation + 2,
      cutover_requested_at: requested_at,
      cutover_completed_at: be_present,
      provider_webhook_xid: nil,
      webhook_secret: nil
    )
    expect(calls).to eq([[:delete_hook, repository.provider_repository_xid, 42], [:remove_import_data]])
    expect(project.reload.import_data).to be_nil
  end
end
