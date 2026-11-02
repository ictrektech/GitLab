# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::RequestStopService, feature_category: :importers do
  include_context 'with import sync stop service helpers'

  let(:authority_state) { :provider_canonical }
  let(:application_generation) { 4 }
  let(:requested_at) { Time.zone.parse('2026-08-25 14:00:00') }
  let(:import_trait) { :import_finished }
  let(:project) do
    create(:project, import_trait, import_type: 'github', import_url: 'https://github.com/octocat/hello-world.git')
  end

  let(:repository) do
    create(
      :import_sync_repository,
      :oauth,
      project: project,
      authority_state: authority_state,
      application_generation: application_generation
    )
  end

  let(:domain_state) { :pending }
  let!(:domain_states) do
    Import::Sync::RepositoryState.domains.keys.index_with do |domain|
      create(:import_sync_repository_state, repository: repository, domain: domain, state: domain_state)
    end
  end

  subject(:service) { described_class.new(repository, requested_at: requested_at) }

  before do
    allow(Import::Sync::Repositories::FinishStopWorker).to receive(:perform_async)
    allow(Gitlab::GithubImport::Logger).to receive(:info)
  end

  def domain_generations
    domain_states.transform_values { |state| state.reload.desired_generation }
  end

  it 'fences older work and schedules one final pass for every data type' do
    expect(service.execute).to eq(application_generation + 1).and be_an(Integer)

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation + 1,
      cutover_requested_at: requested_at,
      cutover_completed_at: nil
    )
    expect(repository).to be_read_only
    expect(lease_context).to have_received(:verify_repository!).with(repository.id)
    domain_states.each_value do |state|
      expect(state.reload).to have_attributes(desired_generation: 1, synced_generation: 0, state: 'pending')
    end
    expect(Import::Sync::Repositories::FinishStopWorker)
      .to have_received(:perform_async).with(repository.id, application_generation + 1).once
  end

  it 'tracks the stop request' do
    expect { service.execute }
      .to trigger_internal_events('request_import_continuous_sync_stop')
      .with(project: project, namespace: project.namespace, additional_properties: { label: 'github' })
  end

  # Unlike a regular update request, the final pass must start fresh even for a running or paused domain.
  context 'when a domain is not pending' do
    where(:starting_state) { [[:running], [:paused], [:delayed], [:degraded], [:current], [:disconnected]] }

    with_them do
      let(:domain_state) { starting_state }

      it 'resets it to pending and requests one more pass' do
        service.execute

        domain_states.each_value do |state|
          expect(state.reload).to have_attributes(state: 'pending', desired_generation: 1, synced_generation: 0)
        end
      end
    end
  end

  it 'writes the generation, state and timestamps in one UPDATE' do
    repository.update!(cutover_completed_at: Time.zone.parse('2026-08-25 13:00:00'))

    updates = repository_updates { service.execute }

    expect(updates.size).to eq(1)
    expect(updates.first).to include(
      '"application_generation"', '"authority_state"', '"cutover_requested_at"', '"cutover_completed_at"'
    )
    expect(repository.reload.cutover_completed_at).to be_nil
  end

  it 'verifies the lease immediately before the write' do
    calls = []
    allow(lease_context).to receive(:verify_repository!) { calls << :verify_repository! }
    allow(repository).to receive(:update!).and_wrap_original do |original, *args|
      calls << :update!
      original.call(*args)
    end

    service.execute

    expect(calls).to eq([:verify_repository!, :update!])
  end

  it 'requeues an existing stop request without advancing its fences again' do
    repository.update!(authority_state: :cutting_over)

    updates = repository_updates { expect(service.execute).to eq(application_generation) }

    expect(updates).to be_empty
    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation,
      cutover_requested_at: nil
    )
    expect(domain_generations.values).to all(eq(0))
    expect(Import::Sync::Repositories::FinishStopWorker)
      .to have_received(:perform_async).with(repository.id, application_generation).once
    expect(Gitlab::GithubImport::Logger).not_to have_received(:info)
  end

  it 'does not track a repeated stop request' do
    repository.update!(authority_state: :cutting_over)

    expect { service.execute }.not_to trigger_internal_events('request_import_continuous_sync_stop')
  end

  it 'accepts cutover_failed and bumps the generation' do
    repository.update!(authority_state: :cutover_failed)

    expect(service.execute).to eq(application_generation + 1)

    expect(repository.reload).to have_attributes(
      authority_state: 'cutting_over',
      application_generation: application_generation + 1
    )
    expect(Import::Sync::Repositories::FinishStopWorker)
      .to have_received(:perform_async).with(repository.id, application_generation + 1)
  end

  context 'when the repository is disconnected' do
    where(:reason) { Import::Sync::Repository.disconnect_reasons.keys.map { |reason| [reason] } }

    with_them do
      it 'raises ConnectionLostError and changes nothing' do
        repository.update!(
          authority_state: :disconnected,
          disconnect_reason: reason,
          restore_authority_state: :provider_canonical
        )

        updates = repository_updates do
          expect { service.execute }.to raise_error(
            described_class::ConnectionLostError, 'GitHub must be reconnected before updates can stop'
          )
        end

        expect(updates).to be_empty
        expect(repository.reload).to have_attributes(
          authority_state: 'disconnected',
          application_generation: application_generation
        )
        expect(domain_generations.values).to all(eq(0))
        expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
      end
    end
  end

  context 'when the state does not allow a stop #security' do
    where(:state) { [[:provisioning], [:bootstrap_canceled], [:gitlab_canonical]] }

    with_them do
      it 'raises InvalidStateError without writing or enqueueing' do
        repository.update!(authority_state: state)

        updates = repository_updates do
          expect { service.execute }.to raise_error(
            described_class::InvalidStateError, 'GitHub updates cannot be stopped in the current state'
          )
        end

        expect(updates).to be_empty
        expect(repository.reload).to have_attributes(
          authority_state: state.to_s,
          application_generation: application_generation
        )
        expect(domain_generations.values).to all(eq(0))
        expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
        expect(Gitlab::GithubImport::Logger).not_to have_received(:info)
      end
    end
  end

  context 'when the import is still running' do
    where(:import_trait) { [[:import_scheduled], [:import_started]] }

    with_them do
      it 'raises InvalidStateError without writing or enqueueing' do
        updates = repository_updates do
          expect { service.execute }.to raise_error(
            described_class::InvalidStateError, 'The import must finish before GitHub updates can stop'
          )
        end

        expect(updates).to be_empty
        expect(repository.reload).to have_attributes(
          authority_state: 'provider_canonical',
          application_generation: application_generation
        )
        expect(domain_generations.values).to all(eq(0))
        expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
      end
    end
  end

  # The stop is the only way out of read-only for a project whose import ended early.
  context 'when the import failed or was canceled' do
    where(:import_trait) { [[:import_failed], [:import_canceled]] }

    with_them do
      it 'accepts the stop' do
        expect(service.execute).to eq(application_generation + 1)

        expect(repository.reload).to be_cutting_over
        expect(Import::Sync::Repositories::FinishStopWorker)
          .to have_received(:perform_async).with(repository.id, application_generation + 1)
      end
    end
  end

  # The caller's copy is stale: only the reload under the row lock sees what another process wrote.
  context 'when another process changed the row after this copy was loaded #security' do
    def change_row_elsewhere(**attributes)
      Import::Sync::Repository.find(repository.id).update!(**attributes)
    end

    it 'raises InvalidStateError for a row that became gitlab_canonical' do
      change_row_elsewhere(authority_state: :gitlab_canonical)

      updates = repository_updates do
        expect { service.execute }.to raise_error(described_class::InvalidStateError)
      end

      expect(updates).to be_empty
      expect(repository.reload).to have_attributes(
        authority_state: 'gitlab_canonical',
        application_generation: application_generation
      )
      expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
    end

    it 'raises ConnectionLostError for a row that became disconnected' do
      change_row_elsewhere(
        authority_state: :disconnected,
        disconnect_reason: :token_revoked,
        restore_authority_state: :provider_canonical
      )

      updates = repository_updates do
        expect { service.execute }.to raise_error(described_class::ConnectionLostError)
      end

      expect(updates).to be_empty
      expect(repository.reload).to have_attributes(
        authority_state: 'disconnected',
        application_generation: application_generation
      )
      expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
    end
  end

  it 'creates a missing domain state row and still schedules its final pass' do
    domain_states['work_items'].destroy!

    service.execute

    expect(repository.sync_states.find_by!(domain: :work_items)).to have_attributes(
      desired_generation: 2,
      synced_generation: 0,
      state: 'pending'
    )
  end

  it 'rolls back the authority transition when scheduling a domain fails' do
    allow(repository).to receive(:sync_states_for_update).and_raise(ActiveRecord::StatementInvalid, 'boom')

    expect { service.execute }.to raise_error(ActiveRecord::StatementInvalid)

    expect(repository.reload).to have_attributes(
      authority_state: 'provider_canonical',
      application_generation: application_generation,
      cutover_requested_at: nil
    )
    expect(domain_generations.values).to all(eq(0))
    expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
    expect(Gitlab::GithubImport::Logger).not_to have_received(:info)
  end

  it 'raises FailedToObtainLockError and changes nothing when the lease is held', :clean_gitlab_redis_shared_state do
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).and_call_original
    lease_key = Import::Sync::Repositories::ApplicationLease.key(repository.id)
    expect(Gitlab::ExclusiveLease.new(lease_key, timeout: 1.minute).try_obtain).to be_truthy

    updates = repository_updates do
      expect { service.execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    end

    expect(updates).to be_empty
    expect(repository.reload).to be_provider_canonical
    expect(domain_generations.values).to all(eq(0))
    expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
  end

  it 'writes nothing when the lease is lost before the write' do
    allow(lease_context).to receive(:verify_repository!)
      .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError)

    updates = repository_updates do
      expect { service.execute }.to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError)
    end

    expect(updates).to be_empty
    expect(repository.reload).to be_provider_canonical
    expect(domain_generations.values).to all(eq(0))
    expect(Import::Sync::Repositories::FinishStopWorker).not_to have_received(:perform_async)
  end

  it 'enqueues FinishStopWorker only after the transaction ends' do
    repository
    baseline = ApplicationRecord.connection.open_transactions
    depths = []
    allow(Import::Sync::Repositories::FinishStopWorker).to receive(:perform_async) do
      depths << ApplicationRecord.connection.open_transactions
    end

    service.execute

    expect(depths).to eq([baseline])
  end

  it 'enqueues FinishStopWorker only after the lease is released' do
    calls = []
    allow(lease).to receive(:execute) do |&block|
      block.call(lease_context).tap { calls << :lease_released }
    end
    allow(Import::Sync::Repositories::FinishStopWorker).to receive(:perform_async) { calls << :enqueued }

    service.execute

    expect(calls).to eq([:lease_released, :enqueued])
  end

  describe 'transition log' do
    let(:log_fields) do
      {
        message: 'import sync repository authority changed',
        import_sync_repository_id: repository.id,
        Labkit::Fields::GL_PROJECT_ID => repository.project_id
      }
    end

    it 'logs the request once at info level, after the transaction commits' do
      repository
      baseline = ApplicationRecord.connection.open_transactions
      depths = []
      allow(Gitlab::GithubImport::Logger).to receive(:info) { depths << ApplicationRecord.connection.open_transactions }

      service.execute

      expect(depths).to eq([baseline])
      expect(Gitlab::GithubImport::Logger).to have_received(:info).once.with(
        **log_fields, from: 'provider_canonical', to: 'cutting_over', application_generation: application_generation + 1
      )
    end

    it 'logs the retry of a failed stop with its previous state' do
      repository.update!(authority_state: :cutover_failed)

      service.execute

      expect(Gitlab::GithubImport::Logger).to have_received(:info).once.with(
        **log_fields, from: 'cutover_failed', to: 'cutting_over', application_generation: application_generation + 1
      )
    end
  end
end
