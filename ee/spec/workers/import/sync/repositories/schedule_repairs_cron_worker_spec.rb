# frozen_string_literal: true

require 'spec_helper'

# Protects the two cron phases: unfinished stops are re-enqueued with the generation seen at scan time, only
# provider-canonical repositories are repaired, and every candidate is reached in a single run.
RSpec.describe Import::Sync::Repositories::ScheduleRepairsCronWorker, feature_category: :importers do
  let(:finish_stop_worker) { Import::Sync::Repositories::FinishStopWorker }
  let(:schedule_repair_worker) { Import::Sync::Repositories::ScheduleRepairWorker }

  subject(:worker) { described_class.new }

  def create_repository(authority_state, **attributes)
    if authority_state == :disconnected
      create(:import_sync_repository, :oauth, :disconnected, **attributes)
    else
      create(:import_sync_repository, :oauth, authority_state: authority_state, **attributes)
    end
  end

  def enqueued_args(worker_class)
    worker_class.jobs.pluck('args')
  end

  it 'is scheduled every 30 minutes' do
    expect(Gitlab::SidekiqConfig.cron_jobs).to include(
      'import_sync_repositories_schedule_repairs_cron_worker' => include(
        'class' => described_class.name,
        'cron' => '*/30 * * * *'
      )
    )
  end

  # The same rows are enqueued by every example, so the deduplication keys in Redis must not outlive one.
  context 'with a repository in every authority state', :clean_gitlab_redis_queues_metadata do
    let_it_be(:repositories) do
      Import::Sync::Repository.authority_states.keys.each_with_index.to_h do |state, index|
        [state, create_repository(state.to_sym, application_generation: 10 + index)]
      end
    end

    it 're-enqueues unfinished stops with their generation, and only those' do
      worker.perform

      expect(enqueued_args(finish_stop_worker)).to contain_exactly(
        [repositories['cutting_over'].id, repositories['cutting_over'].application_generation],
        [repositories['cutover_failed'].id, repositories['cutover_failed'].application_generation]
      )
    end

    it 'repairs provider_canonical repositories only' do
      worker.perform

      expect(enqueued_args(schedule_repair_worker)).to contain_exactly([repositories['provider_canonical'].id])
    end

    it 'does not write to the repositories' do
      expect { worker.perform }
        .not_to change { Import::Sync::Repository.order(:id).pluck(:id, :authority_state, :application_generation) }
    end
  end

  context 'when there are no candidates' do
    it 'does nothing' do
      create_repository(:gitlab_canonical)

      expect(finish_stop_worker).not_to receive(:bulk_perform_async_with_contexts)
      expect(schedule_repair_worker).not_to receive(:bulk_perform_in_with_contexts)

      worker.perform

      expect(worker).to log_extra_metadata_on_done(stop_candidates: 0, repository_candidates: 0)
    end
  end

  context 'when the candidates span several batches' do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 2)
    end

    it 'enqueues every stop candidate in one run' do
      stopping = Array.new(5) { |i| create_repository(i.even? ? :cutting_over : :cutover_failed) }

      worker.perform

      expect(enqueued_args(finish_stop_worker).map(&:first)).to match_array(stopping.map(&:id))
      expect(worker).to log_extra_metadata_on_done(stop_candidates: 5, repository_candidates: 0)
    end

    it 'enqueues every repository repair in one run' do
      repairing = create_list(:import_sync_repository, 5, :oauth, authority_state: :provider_canonical)

      worker.perform

      expect(enqueued_args(schedule_repair_worker)).to match_array(repairing.map { |repository| [repository.id] })
      expect(worker).to log_extra_metadata_on_done(stop_candidates: 0, repository_candidates: 5)
    end

    it 'spreads repairs one batch delay apart and enqueues stops immediately' do
      create_list(:import_sync_repository, 3, :oauth, authority_state: :cutting_over)
      create_list(:import_sync_repository, 5, :oauth, authority_state: :provider_canonical)

      freeze_time do
        worker.perform

        delay = described_class::REPAIR_BATCH_DELAY.to_i
        expect(schedule_repair_worker.jobs.map { |job| job['at'].to_i - Time.current.to_i })
          .to match_array([delay, delay, 2 * delay, 2 * delay, 3 * delay])
        expect(finish_stop_worker.jobs.pluck('at')).to all(be_nil)
      end
    end

    it 'does not re-enqueue itself' do
      create_list(:import_sync_repository, 5, :oauth, authority_state: :cutting_over)
      create_list(:import_sync_repository, 5, :oauth, authority_state: :provider_canonical)

      expect(described_class).not_to receive(:perform_async)
      expect(described_class).not_to receive(:perform_in)

      worker.perform

      expect(described_class.jobs).to be_empty
    end
  end

  describe 'job context' do
    let!(:stopping) { create_repository(:cutting_over) }
    let!(:repairing) { create_repository(:provider_canonical) }

    it 'enqueues each job with its project as context' do
      worker.perform

      expect(finish_stop_worker.jobs.sole).to include('meta.project' => stopping.project.full_path)
      expect(schedule_repair_worker.jobs.sole).to include('meta.project' => repairing.project.full_path)
    end
  end

  describe 'query count' do
    it 'issues no more queries for more candidates, and no COUNT' do
      create_repository(:cutting_over)
      create_repository(:provider_canonical)
      worker.perform

      control = ActiveRecord::QueryRecorder.new { worker.perform }

      create_list(:import_sync_repository, 3, :oauth, authority_state: :cutting_over)
      create_list(:import_sync_repository, 3, :oauth, authority_state: :provider_canonical)

      expect { worker.perform }.not_to exceed_query_limit(control)
      expect(control.log).not_to include(a_string_matching(/COUNT\(/))
    end
  end

  it_behaves_like 'an idempotent worker' do
    let!(:stopping) { create_repository(:cutting_over, application_generation: 3) }
    let!(:repairing) { create_repository(:provider_canonical) }

    # Inline Sidekiq would run the fanned-out jobs themselves; only the scan is under test here.
    before do
      allow(finish_stop_worker).to receive(:bulk_perform_async_with_contexts)
      allow(schedule_repair_worker).to receive(:bulk_perform_in_with_contexts)
    end

    it 'fans out the same candidates on every execution and changes nothing' do
      expect { perform_idempotent_work }
        .not_to change { Import::Sync::Repository.order(:id).pluck(:id, :authority_state, :application_generation) }

      expect(finish_stop_worker).to have_received(:bulk_perform_async_with_contexts).twice
      expect(schedule_repair_worker).to have_received(:bulk_perform_in_with_contexts).twice
    end
  end
end
