# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::ReconcileWorker, feature_category: :importers do
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      authority_state: :provider_canonical,
      project: create(:project, :import_finished)
    )
  end

  let(:source_service) { instance_double(Import::Sync::Repositories::ReconcileSourceService) }
  let(:work_items_service) { instance_double(Import::Sync::Repositories::ReconcileWorkItemsService) }
  let(:lease) { instance_double(Import::Sync::Repositories::ApplicationLease) }
  let(:lease_context) { instance_double(Import::Sync::Repositories::ApplicationLease::Context) }
  let(:application_generation) { repository.application_generation }

  subject(:worker) { described_class.new }

  before do
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
    allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new).and_return(source_service)
    allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new).and_return(work_items_service)
    allow(described_class).to receive(:perform_async)
    allow(described_class).to receive(:perform_in)
  end

  it 'is configured to hold its deduplication lock until the job finishes and reschedule once' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(if_deduplicated: :reschedule_once)
    expect(described_class.get_deduplication_options).not_to include(:including_scheduled)
  end

  it 'retries five times and does not go to the dead set' do
    expect(described_class.get_sidekiq_options).to include('retry' => 5, 'dead' => false)
  end

  it 'shares the GitHub import concurrency limit' do
    stub_application_setting(import_jobs_concurrency_limit: 7)

    expect(described_class.get_concurrency_limit).to eq(7)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [repository.id, application_generation] }

    before do
      allow(source_service).to receive(:execute).and_return(applied_domains: ['source'], follow_up: false)
      allow(work_items_service).to receive(:execute).and_return(applied_domains: ['work_items'], follow_up: false)
    end

    it 'runs both services on every execution' do
      perform_idempotent_work

      expect(source_service).to have_received(:execute).twice
      expect(work_items_service).to have_received(:execute).twice
    end
  end

  it 'logs the applied domains and the follow-up signal' do
    allow(source_service).to receive(:execute).and_return(applied_domains: ['source'], follow_up: false)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: ['work_items'], follow_up: true)
    expect(worker).to receive(:log_extra_metadata_on_done).with(:applied_domains, %w[source work_items])
    expect(worker).to receive(:log_extra_metadata_on_done).with(:follow_up, true)

    worker.perform(repository.id, application_generation)
  end

  context 'when the import did not finish' do
    where(:import_trait, :import_status) do
      [
        [:import_scheduled, 'scheduled'],
        [:import_started, 'started'],
        [:import_failed, 'failed'],
        [:import_canceled, 'canceled']
      ]
    end

    with_them do
      let(:repository) do
        create(
          :import_sync_repository,
          :oauth,
          authority_state: :provider_canonical,
          project: create(:project, import_trait)
        )
      end

      it 'logs and stops without reconciling or rescheduling' do
        expect(Gitlab::GithubImport::Logger).to receive(:info).with(
          message: 'skipping reconciliation, the import did not finish',
          import_sync_repository_id: repository.id,
          Labkit::Fields::GL_PROJECT_ID => repository.project_id,
          import_status: import_status
        )

        worker.perform(repository.id, application_generation)

        expect(Import::Sync::Repositories::ApplicationLease).not_to have_received(:new)
        expect(described_class).not_to have_received(:perform_in)
        expect(described_class).not_to have_received(:perform_async)
      end
    end
  end

  context 'when GitHub rate limits the pass' do
    let(:client) { instance_double(Gitlab::GithubImport::Client, rate_limit_resets_in: 1234) }
    let(:authentication) { instance_double(Import::Sync::Repositories::Authentication, client: client) }

    before do
      allow(Import::Sync::Repositories::Authentication).to receive(:for).with(repository).and_return(authentication)
      allow(work_items_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)
    end

    it 'reschedules for the reset carried by the error' do
      allow(source_service).to receive(:execute)
        .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited', 90))

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(described_class).to have_received(:perform_in).with(90, repository.id, application_generation)
      expect(described_class).not_to have_received(:perform_async)
    end

    it 'neither counts nor clears auth failures' do
      repository.update!(consecutive_auth_failures: 3)
      allow(source_service).to receive(:execute)
        .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited', 90))

      worker.perform(repository.id, application_generation)

      expect(repository.reload.consecutive_auth_failures).to eq(3)
      expect(repository).to be_provider_canonical
    end

    it 'does not run the work-item service on the token the source service just exhausted' do
      allow(source_service).to receive(:execute)
        .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited', 90))

      worker.perform(repository.id, application_generation)

      expect(work_items_service).not_to have_received(:execute)
      expect(described_class).to have_received(:perform_in).with(90, repository.id, application_generation)
    end

    context 'when the reset is too soon to be worth waiting for' do
      where(:reset_in) do
        [[-1], [0], [30]]
      end

      with_them do
        it 'reschedules no sooner than the minimum delay' do
          allow(source_service).to receive(:execute)
            .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited', reset_in))

          worker.perform(repository.id, application_generation)

          expect(described_class).to have_received(:perform_in)
            .with(described_class::RATE_LIMIT_MIN_DELAY, repository.id, application_generation)
        end
      end
    end

    it 'asks GitHub for the reset when the error does not carry one' do
      allow(source_service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError, 'rate limited')
      expect(Gitlab::GithubImport::Logger).to receive(:info).with(
        message: 'GitHub rate limit reached, rescheduling reconciliation',
        import_sync_repository_id: repository.id,
        Labkit::Fields::GL_PROJECT_ID => repository.project_id,
        reschedule_in_s: 1234
      )

      worker.perform(repository.id, application_generation)

      expect(described_class).to have_received(:perform_in).with(1234, repository.id, application_generation)
    end

    it 'falls back to a fixed delay when the reset cannot be read' do
      allow(source_service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError, 'rate limited')
      allow(client).to receive(:rate_limit_resets_in).and_raise(Octokit::Unauthorized)
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(Octokit::Unauthorized), import_sync_repository_id: repository.id)

      worker.perform(repository.id, application_generation)

      expect(described_class).to have_received(:perform_in)
        .with(described_class::RATE_LIMIT_FALLBACK_DELAY, repository.id, application_generation)
    end

    it 'reschedules for the rate limit and tracks the other failure when both services fail' do
      source_error = StandardError.new('source unavailable')
      allow(source_service).to receive(:execute).and_raise(source_error)
      allow(work_items_service).to receive(:execute)
        .and_raise(Gitlab::GithubImport::RateLimitError.new('rate limited', 90))
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(source_error, import_sync_repository_id: repository.id)

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(described_class).to have_received(:perform_in).with(90, repository.id, application_generation)
    end
  end

  it 'applies source and work-item updates under one repository lease for the job generation' do
    repository.update!(application_generation: 5)
    allow(source_service).to receive(:execute).and_return(applied_domains: ['source'], follow_up: false)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: ['work_items'], follow_up: false)

    worker.perform(repository.id, application_generation)

    expect(Import::Sync::Repositories::ApplicationLease).to have_received(:new).with(repository.id)
    expect(Import::Sync::Repositories::ReconcileSourceService)
      .to have_received(:new).with(repository, application_generation: 5)
    expect(Import::Sync::Repositories::ReconcileWorkItemsService)
      .to have_received(:new).with(repository, application_generation: 5)
    expect(source_service).to have_received(:execute).with(lease_context: lease_context)
    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context)
    expect(described_class).not_to have_received(:perform_async)
  end

  it 'queues the same generation when a bounded work-item pass remains nonterminal' do
    allow(source_service).to receive(:execute).and_return(applied_domains: ['source'], follow_up: false)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: ['work_items'], follow_up: true)

    worker.perform(repository.id, application_generation)

    expect(described_class).to have_received(:perform_async).with(repository.id, application_generation)
  end

  it 'attempts work-item reconciliation before retrying a source failure' do
    source_error = StandardError.new('source unavailable')
    allow(source_service).to receive(:execute).and_raise(source_error)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: ['work_items'], follow_up: false)

    expect { worker.perform(repository.id, application_generation) }.to raise_error(source_error)

    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context)
  end

  it 'raises the first failure and tracks the other when both services fail' do
    source_error = StandardError.new('source unavailable')
    work_items_error = StandardError.new('work items bug')
    allow(source_service).to receive(:execute).and_raise(source_error)
    allow(work_items_service).to receive(:execute).and_raise(work_items_error)
    expect(Gitlab::ErrorTracking).to receive(:track_exception)
      .with(work_items_error, import_sync_repository_id: repository.id)

    expect { worker.perform(repository.id, application_generation) }.to raise_error(source_error)
  end

  it 'raises the unauthorized failure and tracks the other when both services fail' do
    source_error = StandardError.new('source unavailable')
    unauthorized = Octokit::Unauthorized.new
    allow(source_service).to receive(:execute).and_raise(source_error)
    allow(work_items_service).to receive(:execute).and_raise(unauthorized)
    expect(Gitlab::ErrorTracking).to receive(:track_exception)
      .with(source_error, import_sync_repository_id: repository.id)

    expect { worker.perform(repository.id, application_generation) }.to raise_error(unauthorized)
  end

  it 'drops the follow-up and leaves it to the retry when the other service fails' do
    allow(source_service).to receive(:execute).and_return(applied_domains: ['source'], follow_up: true)
    allow(work_items_service).to receive(:execute).and_raise(StandardError, 'work items bug')

    expect { worker.perform(repository.id, application_generation) }
      .to raise_error(StandardError, 'work items bug')
    expect(described_class).not_to have_received(:perform_async)
  end

  it 'surfaces a plain StandardError from a service as itself' do
    allow(source_service).to receive(:execute).and_raise(StandardError, 'plain failure')
    allow(work_items_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)

    expect { worker.perform(repository.id, application_generation) }
      .to raise_error(StandardError, 'plain failure')
  end

  it 'aborts immediately when the lease is lost' do
    allow(source_service).to receive(:execute)
      .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
    allow(work_items_service).to receive(:execute)

    expect { worker.perform(repository.id, application_generation) }
      .to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
    expect(work_items_service).not_to have_received(:execute)
  end

  it 'lets lease contention propagate without rescheduling' do
    allow(lease).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

    expect { worker.perform(repository.id, application_generation) }
      .to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    expect(described_class).not_to have_received(:perform_in)
    expect(described_class).not_to have_received(:perform_async)
  end

  it 'does nothing for a stale generation' do
    worker.perform(repository.id, application_generation + 1)

    expect(Import::Sync::Repositories::ApplicationLease).not_to have_received(:new)
  end

  it 'does nothing after the repository is removed' do
    worker.perform(non_existing_record_id, 0)

    expect(Import::Sync::Repositories::ReconcileSourceService).not_to have_received(:new)
    expect(Import::Sync::Repositories::ReconcileWorkItemsService).not_to have_received(:new)
  end

  it 'runs regardless of the import-time flag' do
    stub_feature_flags(github_continuous_import: false)
    allow(source_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)

    worker.perform(repository.id, application_generation)

    expect(source_service).to have_received(:execute)
    expect(work_items_service).to have_received(:execute)
  end

  it 'clears auth failures after a clean pass' do
    repository.update!(consecutive_auth_failures: 3)
    allow(source_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: [], follow_up: false)

    worker.perform(repository.id, application_generation)

    expect(repository.reload.consecutive_auth_failures).to eq(0)
  end

  context 'when the credentials are missing' do
    let(:unauthorized) { Octokit::Unauthorized.new }

    before do
      allow(source_service).to receive(:execute)
        .and_raise(Import::Sync::Errors::MissingCredentialsError, 'Project import data is missing')
      allow(work_items_service).to receive(:execute).and_raise(unauthorized)
    end

    it 'disconnects at once without raising and tracks the other failure' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(unauthorized, import_sync_repository_id: repository.id)
      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
        hash_including(
          Labkit::Fields::ERROR_TYPE => 'Import::Sync::Errors::MissingCredentialsError',
          disconnect_reason: 'token_revoked'
        )
      )

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(repository.reload).to be_disconnected
      expect(repository).to be_disconnected_because_token_revoked
      expect(repository).to be_restore_to_provider_canonical
      expect(described_class).not_to have_received(:perform_async)
    end

    it 'does not disconnect a repository that is no longer provider canonical' do
      repository.update!(authority_state: :disconnected, disconnect_reason: :installation_removed,
        restore_authority_state: :provider_canonical)
      allow(Gitlab::GithubImport::Logger).to receive(:warn)

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(repository.reload).to be_disconnected_because_installation_removed
      expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
        .with(hash_including(disconnect_reason: anything))
    end

    it 'logs that a repository that is no longer provider canonical was left as is' do
      repository.update!(authority_state: :cutting_over)
      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
        Labkit::Fields::LOG_MESSAGE => 'GitHub credentials missing, sync repository left as is',
        Labkit::Fields::GL_PROJECT_ID => repository.project_id,
        import_sync_repository_id: repository.id,
        authority_state: 'cutting_over'
      )

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(repository.reload).to be_cutting_over
    end
  end

  context 'when the refresh token is rejected' do
    let(:bad_refresh_token) { Import::Github::RefreshOauthTokenService::BadRefreshTokenError.new }

    before do
      allow(source_service).to receive(:execute).and_raise(bad_refresh_token)
      allow(work_items_service).to receive(:execute).and_raise(Octokit::Unauthorized)
      allow(Gitlab::ErrorTracking).to receive(:track_exception)
    end

    it 'disconnects at once without raising or counting an auth failure' do
      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
        hash_including(
          Labkit::Fields::ERROR_TYPE => 'Import::Github::RefreshOauthTokenService::BadRefreshTokenError',
          disconnect_reason: 'token_revoked'
        )
      )

      expect { worker.perform(repository.id, application_generation) }.not_to raise_error

      expect(repository.reload).to be_disconnected_because_token_revoked
      expect(repository).to be_restore_to_provider_canonical
      expect(repository.consecutive_auth_failures).to eq(0)
    end
  end

  context 'when retries are exhausted' do
    def exhaust_retries(error)
      described_class.sidekiq_retries_exhausted_block.call({ 'args' => [repository.id, application_generation] }, error)
    end

    it 'counts one auth failure for an unauthorized pass' do
      expect { exhaust_retries(Octokit::Unauthorized.new) }
        .to change { repository.reload.consecutive_auth_failures }.from(0).to(1)
      expect(repository).to be_provider_canonical
    end

    it 'disconnects on the last allowed auth failure' do
      repository.update!(consecutive_auth_failures: Import::Sync::Repository::MAX_CONSECUTIVE_AUTH_FAILURES - 1)
      expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
        hash_including(Labkit::Fields::ERROR_TYPE => 'Octokit::Unauthorized', disconnect_reason: 'token_revoked')
      )

      exhaust_retries(Octokit::Unauthorized.new)

      expect(repository.reload).to be_disconnected_because_token_revoked
      expect(repository).to be_restore_to_provider_canonical
    end

    it 'does not count any other error' do
      expect { exhaust_retries(StandardError.new('boom')) }
        .not_to change { repository.reload.consecutive_auth_failures }
    end

    it 'does not count against a repository that is no longer provider canonical' do
      repository.update!(authority_state: :cutting_over, consecutive_auth_failures: 4)

      exhaust_retries(Octokit::Unauthorized.new)

      expect(repository.reload).to be_cutting_over
      expect(repository.consecutive_auth_failures).to eq(4)
    end

    it 'does nothing after the repository is removed' do
      expect do
        described_class.sidekiq_retries_exhausted_block.call(
          { 'args' => [non_existing_record_id, 0] }, Octokit::Unauthorized.new
        )
      end.not_to raise_error
    end
  end

  context 'with real services and an unauthorized GitHub response' do
    let(:project) { repository.project }

    before do
      project.create_import_data!(credentials: { user: 'oauth-token' })
      allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new).and_call_original
      allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new).and_call_original
      allow(lease_context).to receive_messages(verify!: true, verify_repository!: true, renew!: true)
      allow_next_instance_of(Import::Sync::Repositories::ReconcileSourceService) do |service|
        allow(service).to receive(:fetch_provider_repository).and_raise(Octokit::Unauthorized)
      end
      allow_next_instance_of(Import::Sync::Repositories::ReconcileWorkItemsService) do |service|
        allow(service).to receive(:reconcile_issues).and_raise(Octokit::Unauthorized)
      end
    end

    it 'marks the domain degraded via record_failure and re-raises without an access-loss special case' do
      expect { worker.perform(repository.id, application_generation) }.to raise_error(Octokit::Unauthorized)

      expect(repository.reload).to be_provider_canonical
      expect(repository.consecutive_auth_failures).to eq(0)
      expect(repository.sync_states.find_by!(domain: :source)).to be_degraded
    end
  end
end
