# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search::Zoekt::SchedulingWorker, feature_category: :global_search do
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :always

  it 'is not a pause_control worker' do
    expect(described_class.get_pause_control).not_to eq(:zoekt)
  end

  describe 'deferring on database health' do
    let(:attrs) { described_class.database_health_check_attrs }

    def tables_for(job_args)
      attrs[:block].call(job_args, attrs[:gitlab_schema], attrs[:tables]).last
    end

    it 'watches the tables each writing task writes' do
      expect(tables_for(['auto_index_self_managed'])).to eq(%i[zoekt_enabled_namespaces])
      expect(tables_for(['eviction'])).to eq(%i[zoekt_enabled_namespaces zoekt_replicas zoekt_indices])
      expect(tables_for(['remove_expired_subscriptions']))
        .to eq(%i[zoekt_enabled_namespaces zoekt_replicas zoekt_indices])
      expect(tables_for(['update_replica_states'])).to eq(%i[zoekt_replicas])
    end

    it 'ignores table signals for the initiate job and tasks that only dispatch events' do
      expect(tables_for([])).to be_empty

      (Search::Zoekt::SchedulingService::TASKS.map(&:to_s) - described_class::WRITE_TASK_TABLES.keys).each do |task|
        expect(tables_for([task])).to be_empty
      end
    end

    it 'only lists tasks that exist' do
      expect(described_class::WRITE_TASK_TABLES.keys).to all(be_in(Search::Zoekt::SchedulingService::TASKS.map(&:to_s)))
    end
  end

  describe '#perform' do
    let(:worker) { described_class.new }

    shared_examples 'returns false without executing' do
      it 'returns false without further execution' do
        expect(worker.perform).to be false
        expect(Search::Zoekt::SchedulingService).not_to receive(:execute)
        expect(worker).not_to receive(:initiate)
      end
    end

    context 'when prerequisites are not met' do
      context 'when zoekt indexing is disabled' do
        before do
          allow(Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(false)
        end

        it_behaves_like 'returns false without executing'
      end

      context 'when zoekt indexing is paused' do
        before do
          allow(Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(true)
          allow(Gitlab::CurrentSettings).to receive(:zoekt_indexing_paused?).and_return(true)
        end

        it_behaves_like 'returns false without executing'
      end
    end

    context 'when all prerequisites are met' do
      before do
        allow(Search::Zoekt).to receive(:licensed_and_indexing_enabled?).and_return(true)
        allow(Gitlab::CurrentSettings).to receive(:zoekt_indexing_paused?).and_return(false)
      end

      context 'when no task is provided' do
        it_behaves_like 'an idempotent worker' do
          it 'enqueues a job for each supported task' do
            Search::Zoekt::SchedulingService::TASKS.each do |task|
              expect(described_class).to receive(:perform_async).with(task.to_s)
            end

            worker.perform
          end
        end
      end
    end
  end
end
