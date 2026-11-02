# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::DestroyOldPipelinesWorker, :clean_gitlab_redis_shared_state, feature_category: :continuous_integration do
  include ExclusiveLeaseHelpers

  let_it_be(:project) { create(:project, ci_delete_pipelines_in_seconds: 2.weeks.to_i) }

  let(:cleanup_queue) { Ci::RetentionPolicies::ProjectsCleanupQueue.instance }

  before do
    cleanup_queue.enqueue!(project)
  end

  describe '#perform' do
    let_it_be(:old_pipeline) { create(:ci_pipeline, project: project, created_at: 1.month.ago, locked: :unlocked) }

    let(:worker) { described_class.new }

    subject(:perform) { worker.perform_work }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id] }

      it 'executes the service' do
        expect { perform }.not_to raise_error
      end
    end
  end

  describe '#remaining_work_count' do
    subject(:remaining_work_count) { described_class.new.remaining_work_count }

    it { is_expected.to eq(1) }
  end

  describe 're-enqueuing' do
    let(:worker) { described_class.new }
    let(:service) { instance_double(Ci::Pipelines::AutoCleanupService) }
    let(:destroyed_count) { 30 }
    let(:skipped_count) { 20 }

    before do
      allow(Ci::Pipelines::AutoCleanupService).to receive(:new).with(project: project).and_return(service)
      allow(service).to receive(:execute).and_return(
        ServiceResponse.success(payload: { destroyed_pipelines_size: destroyed_count,
                                           skipped_pipelines_size: skipped_count })
      )
    end

    subject(:perform) { worker.perform_work }

    it 'logs the counts and the project' do
      expect(worker).to receive(:log_extra_metadata_on_done).with(:removed_count, destroyed_count)
      expect(worker).to receive(:log_extra_metadata_on_done).with(:skipped_count, skipped_count)
      expect(worker).to receive(:log_extra_metadata_on_done).with(:project, project.full_path)

      perform
    end

    context 'when destroyed and skipped pipelines together fill a batch' do
      it 're-enqueues the project' do
        expect { perform }.not_to change { cleanup_queue.size }
      end
    end

    context 'when destroyed and skipped pipelines together do not fill a batch' do
      let(:skipped_count) { 19 }

      it 'does not re-enqueue the project' do
        expect { perform }.to change { cleanup_queue.size }.by(-1)
      end
    end
  end

  describe 'project lease' do
    let(:worker) { described_class.new }
    let(:service) { instance_double(Ci::Pipelines::AutoCleanupService) }
    let(:lease_key) { "ci/destroy_old_pipelines_worker:#{project.id}" }
    let(:lease_timeout) { 10.minutes.to_i }

    before do
      allow(Ci::Pipelines::AutoCleanupService).to receive(:new).with(project: project).and_return(service)
      allow(service).to receive(:execute).and_return(
        ServiceResponse.success(payload: { destroyed_pipelines_size: 50, skipped_pipelines_size: 0 })
      )
    end

    subject(:perform) { worker.perform_work }

    context 'when the lease is taken' do
      before do
        stub_exclusive_lease_taken(lease_key, timeout: lease_timeout)
      end

      it 'does not clean up the project' do
        expect(Ci::Pipelines::AutoCleanupService).not_to receive(:new)

        perform
      end

      it 'logs that the lease was taken' do
        expect(worker).to receive(:log_extra_metadata_on_done).with(:lease_taken, true)

        perform
      end
    end

    context 'when the lease is obtained' do
      before do
        stub_exclusive_lease(lease_key, 'uuid', timeout: lease_timeout)
      end

      it 'releases the lease before re-enqueuing the project' do
        expect(Gitlab::ExclusiveLease).to receive(:cancel).with(lease_key, 'uuid').ordered
        expect(cleanup_queue).to receive(:enqueue!).with(project).ordered

        perform
      end

      it 'releases the lease when the cleanup raises' do
        allow(service).to receive(:execute).and_raise(StandardError)

        expect(Gitlab::ExclusiveLease).to receive(:cancel).with(lease_key, 'uuid')

        expect { perform }.to raise_error(StandardError)
      end
    end
  end
end
