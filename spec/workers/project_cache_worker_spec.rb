# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectCacheWorker, feature_category: :source_code_management do
  include ExclusiveLeaseHelpers

  let_it_be_with_reload(:project) { create(:project, :small_repo) }

  let(:worker) { described_class.new }
  let(:lease_key) { ["project_cache_worker", project.id, *statistics.sort].join(":") }
  let(:lease_timeout) { ProjectCacheWorker::LEASE_TIMEOUT }
  let(:margin) { ProjectCacheWorker::TRAILING_UPDATE_MARGIN }
  let(:statistics) { [] }

  describe '#perform' do
    context 'with a non-existing project' do
      it 'does nothing' do
        expect(worker).not_to receive(:update_statistics)

        worker.perform(-1)
      end
    end

    context 'with an existing project without a repository' do
      it 'updates statistics but does not refresh the method cashes' do
        allow_any_instance_of(Repository).to receive(:exists?).and_return(false)

        expect(worker).to receive(:update_statistics)
        expect_any_instance_of(Repository).not_to receive(:refresh_method_caches)

        worker.perform(project.id)
      end
    end

    context 'with an existing project' do
      it 'refreshes the method caches' do
        expect_any_instance_of(Repository).to receive(:refresh_method_caches)
          .with(%i[readme])
          .and_call_original

        worker.perform(project.id, %w[readme])
      end

      context 'with statistics disabled' do
        let(:statistics) { [] }

        it 'does not update the project statistics' do
          expect(worker).not_to receive(:update_statistics)

          worker.perform(project.id, [], [], false)
        end
      end

      context 'with statistics' do
        let(:statistics) { %w[repository_size] }

        it 'updates the project statistics' do
          expect(worker).to receive(:update_statistics)
            .with(kind_of(Project), statistics)
            .and_call_original

          worker.perform(project.id, [], statistics)
        end
      end

      context 'with plain readme' do
        it 'refreshes the method caches' do
          allow(Gitlab::MarkupHelper).to receive_messages(gitlab_markdown?: false, plain?: true)

          expect_any_instance_of(Repository).to receive(:refresh_method_caches)
                                                  .with(%i[readme])
                                                  .and_call_original
          worker.perform(project.id, %w[readme])
        end
      end
    end
  end

  describe '#update_statistics' do
    let(:statistics) { %w[repository_size] }

    context 'when a lease could not be obtained' do
      it 'schedules an update for when the lease expires', :clean_gitlab_redis_shared_state do
        stub_exclusive_lease_taken(lease_key, timeout: lease_timeout)

        expect(Projects::UpdateStatisticsService).not_to receive(:new)

        expect(UpdateProjectStatisticsWorker).to receive(:perform_in)
          .with(lease_timeout + margin, lease_key, project.id, statistics)

        expect(Namespaces::ScheduleAggregationWorker)
          .not_to receive(:perform_async)
          .with(project.namespace_id)

        worker.update_statistics(project, statistics)
      end

      it 'schedules the update directly when the lease expired in the meantime' do
        lease = stub_exclusive_lease_taken(lease_key, timeout: lease_timeout)
        allow(lease).to receive(:ttl).and_return(nil)

        expect(Gitlab::ExclusiveLease).not_to receive(:new).with("#{lease_key}:trailing", anything)
        expect(UpdateProjectStatisticsWorker).to receive(:perform_in)
          .with(margin, lease_key, project.id, statistics)

        worker.update_statistics(project, statistics)
      end
    end

    context 'when a lease could be obtained' do
      it 'updates the project statistics twice', :clean_gitlab_redis_shared_state, :sidekiq_might_not_need_inline do
        stub_exclusive_lease(lease_key, timeout: lease_timeout)

        expect(Projects::UpdateStatisticsService).to receive(:new)
          .with(project, nil, statistics: statistics)
          .and_call_original
          .twice

        expect(UpdateProjectStatisticsWorker).to receive(:perform_in)
          .with(lease_timeout + margin, lease_key, project.id, statistics)
          .and_call_original

        expect(Namespaces::ScheduleAggregationWorker)
          .to receive(:perform_async)
          .with(project.namespace_id)
          .twice

        worker.update_statistics(project, statistics)
      end
    end

    context 'when an earlier update holds the lease', :clean_gitlab_redis_shared_state do
      let(:statistics) { %w[lfs_objects_size] }

      # Redis TTLs do not follow travel_to, so expire the lease period by hand
      def expire_lease
        [lease_key, "#{lease_key}:trailing"].each do |key|
          Gitlab::ExclusiveLease.cancel(key, Gitlab::ExclusiveLease.get_uuid(key))
        end
      end

      it 'refreshes the statistics once the lease expires' do
        worker.update_statistics(project, statistics)
        expire_lease
        UpdateProjectStatisticsWorker.drain

        lfs_object = create(:lfs_objects_project, project: project).lfs_object
        worker.update_statistics(project, statistics)
        expect(project.statistics.reload.lfs_objects_size).to eq(0)

        expire_lease
        UpdateProjectStatisticsWorker.drain

        expect(project.statistics.reload.lfs_objects_size).to eq(lfs_object.size)
      end

      it 'schedules a single trailing refresh per lease period' do
        Gitlab::ExclusiveLease.new(lease_key, timeout: lease_timeout).try_obtain

        expect(UpdateProjectStatisticsWorker).to receive(:perform_in)
          .with(a_value_within(2).of(lease_timeout + margin), lease_key, project.id, statistics)
          .once

        2.times { worker.update_statistics(project, statistics) }
      end

      it 'sizes the trailing key to expire before the lease although Redis rounds the TTL up' do
        lease = stub_exclusive_lease_taken(lease_key, timeout: lease_timeout)
        allow(lease).to receive(:ttl).and_return(3)

        expect(Gitlab::ExclusiveLease).to receive(:new)
          .with("#{lease_key}:trailing", timeout: 1).and_call_original

        worker.update_statistics(project, statistics)
      end
    end

    context 'when project_statistics_trailing_refresh is disabled' do
      before do
        stub_feature_flags(project_statistics_trailing_refresh: false)
      end

      it 'does not schedule an update when a lease could not be obtained' do
        stub_exclusive_lease_taken(lease_key, timeout: lease_timeout)

        expect(Projects::UpdateStatisticsService).not_to receive(:new)
        expect(UpdateProjectStatisticsWorker).not_to receive(:perform_in)

        worker.update_statistics(project, statistics)
      end

      it 'schedules an update after LEASE_TIMEOUT when a lease could be obtained' do
        stub_exclusive_lease(lease_key, timeout: lease_timeout)

        expect(Projects::UpdateStatisticsService).to receive(:new)
          .with(project, nil, statistics: statistics)
          .and_return(instance_double(Projects::UpdateStatisticsService, execute: nil))
        expect(UpdateProjectStatisticsWorker).to receive(:perform_in)
          .with(lease_timeout, lease_key, project.id, statistics)

        worker.update_statistics(project, statistics)
      end
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [project.id, %w[readme], %w[repository_size]] }

    it 'calls Projects::UpdateStatisticsService service twice', :clean_gitlab_redis_shared_state do
      expect(Projects::UpdateStatisticsService).to receive(:new).once.and_return(double(execute: true))
      expect(UpdateProjectStatisticsWorker).to receive(:perform_in).once

      subject
    end
  end
end
