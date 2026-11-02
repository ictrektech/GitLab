# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::ArchiveTraceService, '#execute', feature_category: :continuous_integration do
  subject { described_class.new.execute(job, worker_name: Ci::ArchiveTraceWorker.name) }

  context 'when job is finished' do
    let(:job) { create(:ci_build, :success, :trace_live) }

    it 'creates an archived trace' do
      expect { subject }.not_to raise_error

      expect(job.reload.job_artifacts_trace).to be_exist
    end

    it 'does not schedule an organization isolation status check' do
      expect(::Organizations::CheckOrganizationIsolationStatusWorker).not_to receive(:perform_async)

      subject
    end

    context 'integration hooks' do
      it 'executes archive_trace_hooks integrations with the archive trace data' do
        expect(job.project).to receive(:execute_integrations) do |data, hook_type|
          expect(data).to eq Gitlab::DataBuilder::ArchiveTrace.build(job)
          expect(hook_type).to eq :archive_trace_hooks
        end
        expect { subject }.not_to raise_error
      end
    end

    context 'when trace is already archived' do
      let!(:job) { create(:ci_build, :success, :trace_artifact) }

      it 'ignores an exception' do
        expect { subject }.not_to raise_error
      end

      it 'does not create an archived trace' do
        expect { subject }.not_to change { Ci::JobArtifact.trace.count }
      end

      context 'when live trace chunks still exist' do
        before do
          create(:ci_build_trace_chunk, build: job, chunk_index: 0)
        end

        it 'removes the trace chunks' do
          expect { subject }.to change { job.trace_chunks.count }.to(0)
        end

        context 'when associated data does not exist' do
          before do
            job.job_artifacts_trace.file.remove!
          end

          it 'removes the trace artifact and builds a new one' do
            existing_trace = job.job_artifacts_trace
            expect(existing_trace).to receive(:destroy!).and_call_original

            subject

            expect(job.reload.job_artifacts_trace).to be_present
            expect(job.reload.job_artifacts_trace.file.file).to be_present
          end
        end
      end
    end

    context 'when the pipeline of the job is archived' do
      let(:pipeline) { create(:ci_pipeline, created_at: 2.hours.ago) }
      let(:job) { create(:ci_build, :success, :trace_live, pipeline: pipeline) }

      before do
        stub_application_setting(archive_builds_in_seconds: 1.hour.to_i)
      end

      it 'skips archiving without touching the trace metadata' do
        expect(job).not_to receive(:ensure_trace_metadata!)
        expect(job.trace).not_to receive(:archive!)

        subject
      end
    end

    context 'when the job is out of archival attempts' do
      before do
        create(:ci_build_trace_metadata,
          build: job,
          archival_attempts: Ci::BuildTraceMetadata::MAX_ATTEMPTS + 1,
          last_archival_attempt_at: 1.week.ago)
      end

      it 'skips archiving' do
        expect(job.trace).not_to receive(:archive!)

        subject
      end

      it 'leaves a warning message in sidekiq log' do
        expect(Sidekiq.logger).to receive(:warn).with(
          class: Ci::ArchiveTraceWorker.name,
          message: 'The job is out of archival attempts.',
          job_id: job.id)

        subject
      end

      context 'job has archive and chunks' do
        let(:job) { create(:ci_build, :success, :trace_artifact) }

        before do
          create(:ci_build_trace_chunk, build: job, chunk_index: 0)
        end

        context 'archive is not completed' do
          before do
            job.job_artifacts_trace.file.remove!
          end

          it 'cleanups any stale archive data' do
            expect(job.job_artifacts_trace).to be_present

            subject

            expect(job.reload.job_artifacts_trace).to be_nil
          end
        end

        it 'removes trace chunks' do
          expect { subject }.to change { job.trace_chunks.count }.to(0)
        end
      end
    end

    context 'when the archival process is backed off' do
      before do
        create(:ci_build_trace_metadata,
          build: job,
          archival_attempts: Ci::BuildTraceMetadata::MAX_ATTEMPTS - 1,
          last_archival_attempt_at: 1.hour.ago)
      end

      it 'skips archiving' do
        expect(job.trace).not_to receive(:archive!)

        subject
      end

      it 'leaves a warning message in sidekiq log' do
        expect(Sidekiq.logger).to receive(:warn).with(
          class: Ci::ArchiveTraceWorker.name,
          message: 'The job can not be archived right now.',
          job_id: job.id)

        subject
      end
    end
  end

  context 'when job is running' do
    let(:job) { create(:ci_build, :running, :trace_live) }

    it 'increments Prometheus counter, sends crash report to Sentry and ignore an error for continuing to archive' do
      expect(Gitlab::ErrorTracking)
        .to receive(:track_and_raise_for_dev_exception)
        .with(::Gitlab::Ci::Trace::ArchiveError,
          issue_url: 'https://gitlab.com/gitlab-org/gitlab-foss/issues/51502',
          job_id: job.id).once

      expect(Sidekiq.logger).to receive(:warn).with(
        class: Ci::ArchiveTraceWorker.name,
        message: "Failed to archive trace. message: Job is not finished yet.",
        job_id: job.id).and_call_original

      expect(Gitlab::Metrics)
        .to receive(:counter)
        .with(:job_trace_archive_failed_total, "Counter of failed attempts of trace archiving")
        .and_call_original

      expect { subject }.not_to raise_error
      expect(job.trace_metadata.archival_attempts).to eq(1)
    end
  end

  describe '#batch_execute', :clean_gitlab_redis_shared_state do
    let(:service) { described_class.new }
    let(:job) { create(:ci_build, :success, :trace_live, finished_at: 1.day.ago) }
    let(:job2) { create(:ci_build, :success, :trace_live, finished_at: 1.day.ago) }
    let(:cursor_key) { described_class::CURSOR_KEY }

    subject { service.batch_execute(worker_name: Ci::ArchiveTraceWorker.name) }

    before do
      stub_application_setting(ci_job_live_trace_enabled: true)
      job
      job2
    end

    def read_cursor(field = 'cursor')
      Gitlab::Redis::SharedState.with { |redis| redis.hget(cursor_key, field) }
    end

    def write_cursor(value, pass_end: nil)
      Gitlab::Redis::SharedState.with do |redis|
        redis.hset(cursor_key, 'cursor', value)
        redis.hset(cursor_key, 'pass_end', pass_end) if pass_end
      end
    end

    shared_examples 'archives stale traces in batches' do
      it 'archives multiple traces' do
        expect { subject }.not_to raise_error

        expect(job.reload.job_artifacts_trace).to be_exist
        expect(job2.reload.job_artifacts_trace).to be_exist
      end

      it 'processes traces independently' do
        allow_next_instance_of(Gitlab::Ci::Trace) do |instance|
          orig_method = instance.method(:archive!)
          allow(instance).to receive(:archive!) do
            raise('Unexpected error') if instance.job.id == job.id

            orig_method.call
          end
        end

        expect { subject }.not_to raise_error

        expect(job.reload.job_artifacts_trace).to be_nil
        expect(job2.reload.job_artifacts_trace).to be_exist
      end

      context 'when timeout is reached' do
        before do
          stub_const("#{described_class}::LOOP_TIMEOUT", 0.seconds)
        end

        it 'stops executing traces' do
          expect { subject }.not_to raise_error

          expect(job.reload.job_artifacts_trace).to be_nil
        end
      end

      context 'when loop limit is reached' do
        before do
          stub_const("#{described_class}::LOOP_LIMIT", -1)
        end

        it 'skips archiving' do
          expect(job.trace).not_to receive(:archive!)

          subject
        end

        it 'stops executing traces' do
          expect(Sidekiq.logger).to receive(:warn).with(
            class: Ci::ArchiveTraceWorker.name,
            message: "Loop limit reached.",
            job_id: job.id)

          expect { subject }.not_to raise_error

          expect(job.reload.job_artifacts_trace).to be_nil
        end
      end
    end

    it_behaves_like 'archives stale traces in batches'

    context 'with the trace chunk cursor' do
      let(:job3) { create(:ci_build, :success, :trace_live, finished_at: 1.day.ago) }

      before do
        job3
        stub_const("#{described_class}::BATCH_SIZE", 1)
      end

      it 'archives every stale trace across batches and clears the cursor' do
        expect(service).to receive(:execute).exactly(3).times.and_call_original

        expect(subject).to include(processed: 3, completed_cycle: true, cursor_start: 0, cursor_end: nil)

        expect([job, job2, job3].map { |build| build.reload.job_artifacts_trace }).to all(be_exist)
        expect(Ci::BuildTraceChunk.count).to eq(0)
        expect(Gitlab::Redis::SharedState.with { |redis| redis.exists?(cursor_key) }).to be(false)
      end

      it 'ends the pass at the newest build with chunks when it started' do
        late_job = nil
        allow(service).to receive(:archive_stale_build).and_wrap_original do |original, *args|
          late_job ||= create(:ci_build, :success, :trace_live, finished_at: 1.day.ago)
          original.call(*args)
        end

        expect(subject).to include(processed: 3, completed_cycle: true, pass_end: job3.id)

        expect(late_job.reload.job_artifacts_trace).to be_nil
        expect(described_class.new.batch_execute(worker_name: Ci::ArchiveTraceWorker.name))
          .to include(processed: 1, pass_end: late_job.id)
        expect(late_job.reload.job_artifacts_trace).to be_exist
      end

      it 'keeps the pass end of a resumed pass' do
        write_cursor(job.id, pass_end: job2.id)

        expect(subject).to include(processed: 1, completed_cycle: true, cursor_start: job.id, pass_end: job2.id)

        expect(job2.reload.job_artifacts_trace).to be_exist
        expect(job3.reload.job_artifacts_trace).to be_nil
      end

      it 'starts a new pass when the stored cursor is unreadable' do
        write_cursor('not-a-number', pass_end: 'not-a-number')

        expect(subject).to include(processed: 3, cursor_start: 0, pass_end: job3.id, completed_cycle: true)
      end

      it 'completes the pass straight away when there are no chunks' do
        Ci::BuildTraceChunk.delete_all

        expect(subject).to include(processed: 0, completed_cycle: true, pass_end: 0)
      end

      it 'resumes after the stored cursor' do
        write_cursor(job.id)

        expect(subject).to include(processed: 2, cursor_start: job.id)

        expect(job.reload.job_artifacts_trace).to be_nil
        expect(job2.reload.job_artifacts_trace).to be_exist
        expect(job3.reload.job_artifacts_trace).to be_exist
      end

      it 'archives the other builds when one has no pipeline' do
        job2.update_column(:commit_id, nil)

        expect(subject).to include(processed: 3, completed_cycle: true)

        expect(job.reload.job_artifacts_trace).to be_exist
        expect(job2.reload.job_artifacts_trace).to be_nil
        expect(job3.reload.job_artifacts_trace).to be_exist
      end

      context 'when the loop limit is reached' do
        before do
          stub_const("#{described_class}::LOOP_LIMIT", 1)
        end

        it 'stores the cursor at the last processed build' do
          expect(subject).to include(processed: 1, limit_reached: true, completed_cycle: false, cursor_end: job.id)

          expect(read_cursor).to eq(job.id.to_s)
          expect(read_cursor('pass_end')).to eq(job3.id.to_s)
          expect(Gitlab::Redis::SharedState.with { |redis| redis.ttl(cursor_key) }).to be_within(60).of(1.week.to_i)
          expect(job2.reload.job_artifacts_trace).to be_nil
        end

        it 'archives the remaining builds on the next runs' do
          3.times { described_class.new.batch_execute(worker_name: Ci::ArchiveTraceWorker.name) }

          expect([job, job2, job3].map { |build| build.reload.job_artifacts_trace }).to all(be_exist)
        end
      end

      it 'keeps the progress of a run that fails part way' do
        allow(Ci::Build).to receive(:stale_with_keys).and_call_original
        allow(Ci::Build).to receive(:stale_with_keys)
          .with([[job3.id, job3.partition_id]]).and_raise(ActiveRecord::QueryCanceled)

        expect { subject }.to raise_error(ActiveRecord::QueryCanceled)

        expect(read_cursor).to eq(job2.id.to_s)
      end

      context 'when the timeout is reached during a batch' do
        before do
          stub_const("#{described_class}::BATCH_SIZE", 10)
          allow(service).to receive(:over_time?).and_return(false, false, true)
        end

        it 'stores the cursor at the last processed build' do
          expect(subject).to include(processed: 1, over_time: true, cursor_end: job.id)

          expect(read_cursor).to eq(job.id.to_s)
        end
      end

      context 'when builds in the window do not qualify' do
        let(:recent_job) { create(:ci_build, :success, :trace_live, finished_at: 1.hour.ago) }
        let(:running_job) { create(:ci_build, :running, :trace_live) }

        before do
          stub_const("#{described_class}::BATCH_SIZE", 10)
          recent_job
          running_job
        end

        it 'moves the cursor past them without processing them' do
          expect(subject).to include(processed: 3, completed_cycle: true)

          expect(recent_job.reload.job_artifacts_trace).to be_nil
          expect(running_job.reload.job_artifacts_trace).to be_nil
          expect(Ci::BuildTraceChunk.where(build_id: [recent_job.id, running_job.id]).count).to eq(2)
        end
      end

      context 'when a pipeline is archived' do
        let(:archived_pipeline) { create(:ci_pipeline, created_at: 2.hours.ago) }
        let(:archived_job) do
          create(:ci_build, :success, :trace_live, pipeline: archived_pipeline, finished_at: 1.day.ago)
        end

        before do
          stub_const("#{described_class}::LOOP_LIMIT", 3)
          stub_application_setting(archive_builds_in_seconds: 1.hour.to_i)
          archived_job
        end

        it 'skips its builds without counting them toward the loop limit' do
          allow(service).to receive(:execute).and_call_original
          expect(service).not_to receive(:execute).with(archived_job, anything)

          expect(subject).to include(processed: 3, skipped_archived_pipeline: 1, completed_cycle: true)
        end
      end

      it 'preloads the associations used by #execute' do
        expect(service).to receive(:execute).exactly(3).times do |build, **|
          expect(build.association(:pipeline)).to be_loaded
          expect(build.association(:project)).to be_loaded
          expect(build.association(:pending_state)).to be_loaded
        end

        subject
      end
    end

    context 'when ci_archive_traces_cron_cursor is disabled' do
      before do
        stub_feature_flags(ci_archive_traces_cron_cursor: false)
      end

      it_behaves_like 'archives stale traces in batches'

      it 'does not return run stats' do
        expect(subject).not_to be_a(Hash)
      end
    end
  end
end
