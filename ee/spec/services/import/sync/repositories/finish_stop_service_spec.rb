# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::FinishStopService, feature_category: :importers do
  include_context 'with import sync stop service helpers'

  let(:application_generation) { 6 }
  let(:import_trait) { :import_finished }
  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: create(:project, import_trait, import_type: 'github'),
      authority_state: :cutting_over,
      application_generation: application_generation
    )
  end

  let(:lost_lease_error) { Import::Sync::Repositories::ApplicationLease::LostLeaseError }
  let(:completed_at) { Time.zone.parse('2026-08-25 15:03:00') }
  let(:now) { -> { completed_at } }
  let(:terminal_result) { { applied_domains: [], follow_up: false } }

  let(:source_service) do
    instance_double(Import::Sync::Repositories::ReconcileSourceService, execute: terminal_result)
  end

  let(:work_items_service) do
    instance_double(Import::Sync::Repositories::ReconcileWorkItemsService, execute: terminal_result)
  end

  let!(:domain_states) do
    Import::Sync::RepositoryState.domains.keys.index_with do |domain|
      create(
        :import_sync_repository_state,
        repository: repository,
        domain: domain,
        desired_generation: 1,
        synced_generation: 1,
        state: :current
      )
    end
  end

  subject(:service) do
    described_class.new(repository, application_generation: application_generation, now: now)
  end

  before do
    allow(Import::Sync::Repositories::ReconcileSourceService).to receive(:new).and_return(source_service)
    allow(Import::Sync::Repositories::ReconcileWorkItemsService).to receive(:new).and_return(work_items_service)
    allow(Gitlab::GithubImport::Logger).to receive(:info)
    allow(Gitlab::GithubImport::Logger).to receive(:warn)
  end

  it 'makes GitLab editable once no domain is lagging' do
    calls = []
    allow(lease_context).to receive(:verify_repository!) { calls << :verify_repository! }
    allow(lease_context).to receive(:renew!) { calls << :renew! }
    allow(source_service).to receive(:execute) { calls << :source }.and_return(terminal_result)
    allow(work_items_service).to receive(:execute) { calls << :work_items }.and_return(terminal_result)
    allow(repository).to receive(:update!).and_wrap_original do |original, *args|
      calls << :update!
      original.call(*args)
    end

    expect(service.execute).to be(true)

    expect(repository.reload).to have_attributes(
      authority_state: 'gitlab_canonical',
      application_generation: application_generation + 1,
      cutover_completed_at: completed_at
    )
    final_pass = { application_generation: application_generation, allow_cutover: true, now: now }
    expect(Import::Sync::Repositories::ReconcileSourceService).to have_received(:new).with(repository, **final_pass)
    expect(Import::Sync::Repositories::ReconcileWorkItemsService).to have_received(:new).with(repository, **final_pass)
    expect(source_service).to have_received(:execute).with(lease_context: lease_context)
    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context)
    expect(calls.last(2)).to eq([:verify_repository!, :update!])
  end

  it 'tracks the completed stop once, with the final pass as the reason' do
    expect { service.execute }
      .to trigger_internal_events('complete_import_continuous_sync_stop')
      .with(
        project: repository.project,
        namespace: repository.project.namespace,
        additional_properties: { label: 'github', property: 'final_pass' }
      )
  end

  it 'does not track the stop again when a retry finds it finished' do
    service.execute

    expect { described_class.new(repository, application_generation: application_generation, now: now).execute }
      .to raise_error(described_class::StaleStopError)
      .and not_trigger_internal_events('complete_import_continuous_sync_stop')
  end

  it 'does not track a stop that fails' do
    allow(source_service).to receive(:execute).and_raise(StandardError)

    expect { service.execute }
      .to raise_error(StandardError)
      .and not_trigger_internal_events('complete_import_continuous_sync_stop')
  end

  # Work-item pagination may require several bounded invocations. A nonterminal page is ordinary progress,
  # not a failed cutover: the project stays read-only and the same fenced stop finishes after the last page.
  it 'keeps cutting over until the terminal work-item page is durable' do
    allow(work_items_service).to receive(:execute).and_return(
      { applied_domains: [], follow_up: true },
      { applied_domains: %w[work_items], follow_up: false }
    )

    expect(repository_updates { expect(service.execute).to be(false) }).to be_empty

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation,
      cutover_completed_at: nil
    )
    expect(repository).to be_read_only
    expect(lease_context).to have_received(:renew!).once

    expect(service.execute).to be(true)

    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context).twice
    expect(lease_context).to have_received(:renew!).exactly(3).times
    expect(Import::Sync::Repositories::ApplicationLease).to have_received(:new).with(repository.id).twice
    expect(repository.reload).to have_attributes(
      authority_state: 'gitlab_canonical',
      application_generation: application_generation + 1,
      cutover_completed_at: completed_at
    )
  end

  it 'keeps cutting over while the source pass reports a follow-up' do
    allow(source_service).to receive(:execute).and_return(
      { applied_domains: [], follow_up: true },
      { applied_domains: %w[inventory source], follow_up: false }
    )

    expect(repository_updates { expect(service.execute).to be(false) }).to be_empty

    expect(work_items_service).not_to have_received(:execute)
    expect(lease_context).not_to have_received(:renew!)
    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation,
      cutover_completed_at: nil
    )

    expect(service.execute).to be(true)

    expect(source_service).to have_received(:execute).with(lease_context: lease_context).twice
    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context).once
    expect(repository.reload).to be_gitlab_canonical
  end

  it 'does not hold a transaction open around the reconcile passes' do
    baseline = ApplicationRecord.connection.open_transactions
    depths = []
    allow(source_service).to receive(:execute) do
      depths << ApplicationRecord.connection.open_transactions
      terminal_result
    end
    allow(work_items_service).to receive(:execute) do
      depths << ApplicationRecord.connection.open_transactions
      terminal_result
    end

    service.execute

    expect(depths).to eq([baseline, baseline])
  end

  it 'keeps the project read-only when a final provider check fails' do
    allow(source_service).to receive(:execute).and_raise(StandardError, 'provider failure')

    expect { service.execute }.to raise_error(StandardError, 'provider failure')

    expect(repository.reload).to be_cutover_failed
    expect(repository).to be_read_only
    expect(work_items_service).not_to have_received(:execute)
  end

  it 'keeps the project read-only when the work-items pass fails after the source pass' do
    allow(work_items_service).to receive(:execute).and_raise(StandardError, 'provider failure')

    expect { service.execute }.to raise_error(StandardError, 'provider failure')

    expect(repository.reload).to be_cutover_failed
    expect(repository).to be_read_only
    expect(source_service).to have_received(:execute)
  end

  context 'when the import failed or was canceled' do
    where(:import_trait, :import_status) { [[:import_failed, 'failed'], [:import_canceled, 'canceled']] }

    with_them do
      before do
        domain_states['source'].update!(desired_generation: 2, state: :degraded)
      end

      it 'completes the stop without the final pass' do
        expect { expect(service.execute).to be(true) }
          .to trigger_internal_events('complete_import_continuous_sync_stop')
          .with(
            project: repository.project,
            namespace: repository.project.namespace,
            additional_properties: { label: 'github', property: 'import_not_finished' }
          )

        expect(repository.reload).to have_attributes(
          authority_state: 'gitlab_canonical',
          application_generation: application_generation + 1,
          cutover_completed_at: completed_at
        )
        expect(Import::Sync::Repositories::ReconcileSourceService).not_to have_received(:new)
        expect(Import::Sync::Repositories::ReconcileWorkItemsService).not_to have_received(:new)
        expect(Gitlab::GithubImport::Logger).to have_received(:info).with(
          hash_including(
            message: 'stop completed without the final pass, the import did not finish',
            import_status: import_status
          )
        )
      end
    end
  end

  context 'when the GitHub repository is gone' do
    where(:error) do
      [
        [Octokit::NotFound],
        [Import::Sync::Errors::ProviderIdentityError]
      ]
    end

    with_them do
      before do
        domain_states['source'].update!(desired_generation: 2, state: :degraded)
        allow(source_service).to receive(:execute).and_raise(error)
      end

      it 'completes the stop without the final pass' do
        expect { expect(service.execute).to be(true) }
          .to trigger_internal_events('complete_import_continuous_sync_stop')
          .with(
            project: repository.project,
            namespace: repository.project.namespace,
            additional_properties: { label: 'github', property: 'github_repository_gone' }
          )

        expect(repository.reload).to have_attributes(
          authority_state: 'gitlab_canonical',
          application_generation: application_generation + 1,
          cutover_completed_at: completed_at
        )
        expect(work_items_service).not_to have_received(:execute)
        expect(Gitlab::GithubImport::Logger).to have_received(:warn).with(
          hash_including(
            message: 'GitHub repository unavailable, completing the stop without the final pass',
            Labkit::Fields::ERROR_TYPE => error.name
          )
        )
      end
    end

    it 'treats a 404 from the work-items pass as a failure, since it can be a single missing pull request' do
      allow(work_items_service).to receive(:execute).and_raise(Octokit::NotFound)

      expect { service.execute }.to raise_error(Octokit::NotFound)

      expect(repository.reload).to be_cutover_failed
    end

    it 'does not complete a stale stop' do
      allow(source_service).to receive(:execute) do
        Import::Sync::Repository.find(repository.id).update!(application_generation: application_generation + 1)
        raise Octokit::NotFound
      end

      expect { service.execute }.to raise_error(described_class::StaleStopError)

      expect(repository.reload).to be_cutting_over
    end
  end

  context 'when the GitHub token is rejected' do
    before do
      allow(source_service).to receive(:execute).and_raise(Octokit::Unauthorized)
    end

    it 'counts the auth failure and marks the stop failed' do
      expect { service.execute }.to raise_error(Octokit::Unauthorized)

      expect(repository.reload).to have_attributes(authority_state: 'cutover_failed', consecutive_auth_failures: 1)
    end

    it 'disconnects once the failures reach the limit, so the user can reconnect' do
      repository.update!(consecutive_auth_failures: Import::Sync::Repository::MAX_CONSECUTIVE_AUTH_FAILURES - 1)

      expect { service.execute }.to raise_error(Octokit::Unauthorized)

      expect(repository.reload).to have_attributes(
        authority_state: 'disconnected',
        disconnect_reason: 'token_revoked',
        restore_authority_state: 'provider_canonical'
      )
    end
  end

  it 'leaves the stop in progress on a rate limit, for the worker to reschedule' do
    allow(source_service).to receive(:execute).and_raise(Gitlab::GithubImport::RateLimitError)

    expect(repository_updates { expect { service.execute }.to raise_error(Gitlab::GithubImport::RateLimitError) })
      .to be_empty

    expect(repository.reload).to be_cutting_over
  end

  it 'reopens the same fenced stop attempt when a background retry succeeds' do
    repository.update!(authority_state: :cutover_failed)

    expect(service.execute).to be(true)

    expect(repository.reload).to have_attributes(
      authority_state: 'gitlab_canonical',
      application_generation: application_generation + 1,
      cutover_completed_at: completed_at
    )
    expect(source_service).to have_received(:execute).with(lease_context: lease_context)
    expect(work_items_service).to have_received(:execute).with(lease_context: lease_context)
  end

  it 'does not reopen a failed stop that belongs to another generation' do
    repository.update!(authority_state: :cutover_failed, application_generation: application_generation + 1)

    expect(repository_updates { expect { service.execute }.to raise_error(described_class::StaleStopError) })
      .to be_empty

    expect(repository.reload).to have_attributes(
      authority_state: 'cutover_failed',
      application_generation: application_generation + 1
    )
    expect(source_service).not_to have_received(:execute)
  end

  it 'does not mark a stale generation failed' do
    repository.update!(application_generation: application_generation + 1)

    expect { service.execute }.to raise_error(described_class::StaleStopError)

    expect(repository.reload).to be_cutting_over
    expect(source_service).not_to have_received(:execute)
    expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
  end

  it 'does not mark a newer attempt failed when the pass fails after the generation moved' do
    allow(source_service).to receive(:execute) do
      Import::Sync::Repository.find(repository.id).update!(application_generation: application_generation + 1)
      raise StandardError, 'provider failure'
    end

    expect { service.execute }.to raise_error(StandardError, 'provider failure')

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation + 1
    )
    expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
  end

  context 'when the row is not part of this stop' do
    where(:row_attributes) do
      [
        [{ authority_state: :provider_canonical }],
        [{ authority_state: :provisioning }],
        [{ authority_state: :bootstrap_canceled }],
        [{ authority_state: :gitlab_canonical }],
        [{ authority_state: :disconnected, disconnect_reason: :token_revoked,
           restore_authority_state: :provider_canonical }]
      ]
    end

    with_them do
      before do
        repository.update!(row_attributes)
      end

      it 'raises without writing or reconciling #security' do
        expect(repository_updates { expect { service.execute }.to raise_error(described_class::StaleStopError) })
          .to be_empty

        expect(repository.reload).to have_attributes(
          authority_state: row_attributes[:authority_state].to_s,
          application_generation: application_generation
        )
        expect(source_service).not_to have_received(:execute)
        expect(work_items_service).not_to have_received(:execute)
      end
    end
  end

  it 'does not complete when another instance changed the row after the last reconcile pass #security' do
    allow(work_items_service).to receive(:execute) do
      Import::Sync::Repository.find(repository.id).update!(application_generation: application_generation + 1)
      terminal_result
    end

    expect { service.execute }.to raise_error(described_class::StaleStopError)

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation + 1,
      cutover_completed_at: nil
    )
    expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
  end

  it 'does not complete while a domain is lagging' do
    domain_states['work_items'].update!(desired_generation: 2)
    allow(work_items_service).to receive(:execute).and_return(applied_domains: %w[work_items], follow_up: false)

    expect { service.execute }.to raise_error(
      described_class::IncompleteFinalCheckError,
      'The final GitHub update did not complete for every data type'
    )

    expect(repository.reload).to be_cutover_failed
    expect(repository).to be_read_only
  end

  it 'treats a reconcile result with follow_up false and nothing applied as not proof of currency' do
    domain_states['source'].update!(desired_generation: 2)

    expect { service.execute }.to raise_error(described_class::IncompleteFinalCheckError)

    expect(repository.reload).to have_attributes(authority_state: 'cutover_failed', cutover_completed_at: nil)
  end

  it 'does not complete when a domain state row is missing, since a recreated row starts out lagging' do
    domain_states['inventory'].destroy!

    expect { service.execute }.to raise_error(described_class::IncompleteFinalCheckError)

    expect(repository.reload).to be_cutover_failed
  end

  it 'lets lease contention propagate without touching the row' do
    allow(lease).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

    updates = repository_updates do
      expect { service.execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    end

    expect(updates).to be_empty

    expect(repository.reload).to be_cutting_over
    expect(source_service).not_to have_received(:execute)
  end

  it 'does not mark failed when the lease is lost' do
    allow(lease_context).to receive(:renew!).and_raise(lost_lease_error)

    expect(repository_updates { expect { service.execute }.to raise_error(lost_lease_error) }).to be_empty

    expect(repository.reload).to be_cutting_over
    expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
  end

  # Another worker may hold the lease by now; it must keep its stop, and the caller still sees the pass error.
  it 'does not mark failed, and still raises the pass error, when the lease is lost before the failure is recorded' do
    allow(source_service).to receive(:execute) do
      allow(lease_context).to receive(:verify_repository!).and_raise(lost_lease_error)
      raise StandardError, 'provider failure'
    end

    expect(repository_updates { expect { service.execute }.to raise_error(StandardError, 'provider failure') })
      .to be_empty

    expect(repository.reload).to be_cutting_over
    expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
  end

  it 'does not write when the lease is lost after the final checks and before the write #security' do
    allow(repository).to receive(:sync_states_for_update).and_wrap_original do |original, *args|
      original.call(*args).tap do
        allow(lease_context).to receive(:verify_repository!).and_raise(lost_lease_error)
      end
    end

    expect(repository_updates { expect { service.execute }.to raise_error(lost_lease_error) }).to be_empty

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation,
      cutover_completed_at: nil
    )
  end

  it 'performs exactly one UPDATE that sets gitlab_canonical #security' do
    updates = repository_updates { service.execute }

    expect(updates.size).to eq(1)
    expect(updates.first).to include('"authority_state"', '"application_generation"', '"cutover_completed_at"')
    expect(repository.reload).to be_gitlab_canonical
  end

  describe 'transition logs' do
    let(:log_fields) do
      {
        message: 'import sync repository authority changed',
        import_sync_repository_id: repository.id,
        Labkit::Fields::GL_PROJECT_ID => repository.project_id
      }
    end

    it 'logs the completion once at info level, after the transaction commits' do
      baseline = ApplicationRecord.connection.open_transactions
      depths = []
      allow(Gitlab::GithubImport::Logger).to receive(:info) { depths << ApplicationRecord.connection.open_transactions }

      service.execute

      expect(depths).to eq([baseline])
      expect(Gitlab::GithubImport::Logger).to have_received(:info).once.with(
        **log_fields, from: 'cutting_over', to: 'gitlab_canonical', application_generation: application_generation + 1
      )
    end

    it 'logs the reopening of a failed stop at info level' do
      repository.update!(authority_state: :cutover_failed)

      service.execute

      expect(Gitlab::GithubImport::Logger).to have_received(:info).with(
        **log_fields, from: 'cutover_failed', to: 'cutting_over', application_generation: application_generation
      ).once
    end

    it 'logs the failed stop once at warn level' do
      allow(source_service).to receive(:execute).and_raise(StandardError, 'provider failure')

      expect { service.execute }.to raise_error(StandardError)

      expect(Gitlab::GithubImport::Logger).to have_received(:warn).once.with(
        **log_fields,
        from: 'cutting_over',
        to: 'cutover_failed',
        application_generation: application_generation,
        Labkit::Fields::ERROR_TYPE => 'StandardError'
      )
    end

    it 'logs nothing for a follow-up that leaves the stop in progress' do
      allow(source_service).to receive(:execute).and_return(applied_domains: [], follow_up: true)

      service.execute

      expect(Gitlab::GithubImport::Logger).not_to have_received(:info)
      expect(Gitlab::GithubImport::Logger).not_to have_received(:warn)
    end
  end
end
