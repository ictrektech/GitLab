# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CreatePipelineWorker, :clean_gitlab_redis_shared_state, feature_category: :pipeline_composition do
  describe '.sidekiq_retries_exhausted' do
    let_it_be(:project) { create(:project) }
    let(:creation_params) { {} }
    let(:job) { { 'args' => [project.id, non_existing_record_id, 'main', :push, {}, creation_params] } }

    it 'calls perform_failure with extracted args and the exception' do
      exception = RuntimeError.new('something went wrong')

      expect_next_instance_of(described_class) do |worker|
        expect(worker).to receive(:perform_failure).with(project.id, 'main', exception, {})
      end

      described_class.sidekiq_retries_exhausted_block.call(job, exception)
    end

    context 'when pipeline_creation_request is present' do
      let(:pipeline_creation_request) { { 'key' => 'test-key', 'id' => 'test-id' } }
      let(:creation_params) { { 'pipeline_creation_request' => pipeline_creation_request } }

      it 'marks the pipeline creation request as failed' do
        expect(Ci::PipelineCreation::Requests)
          .to receive(:failed)
          .with(pipeline_creation_request, 'Cannot create a pipeline after multiple retries.')

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))
      end
    end

    context 'when pipeline_creation_request is not present' do
      it 'does not call failed' do
        expect(Ci::PipelineCreation::Requests).not_to receive(:failed)

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))
      end
    end

    context 'when the request is a ref pipeline creation request' do
      let_it_be(:project) { create(:project, :repository) }
      let_it_be(:auto_merge_merge_request) do
        create(:merge_request, :merge_when_checks_pass,
          source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let(:ref_request) { Ci::PipelineCreation::Requests.start_for_ref(project, 'refs/heads/feature') }
      let(:job) do
        { 'args' => [project.id, non_existing_record_id, 'refs/heads/feature', :push, {},
          { 'pipeline_creation_request' => ref_request }] }
      end

      it 'fails the request and runs auto-merge for the merge requests from that branch' do
        expect(AutoMergeProcessWorker).to receive(:perform_async)
          .with({ 'merge_request_id' => [auto_merge_merge_request.id] })

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))

        expect(Ci::PipelineCreation::Requests.hget(ref_request)).to be_nil
      end

      context 'when the project no longer exists' do
        let(:job) do
          { 'args' => [non_existing_record_id, non_existing_record_id, 'refs/heads/feature', :push, {},
            { 'pipeline_creation_request' => ref_request }] }
        end

        it 'fails the request without running auto-merge' do
          expect(AutoMergeProcessWorker).not_to receive(:perform_async)

          described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))

          expect(Ci::PipelineCreation::Requests.hget(ref_request)).to be_nil
        end
      end
    end

    context 'when creation_params is nil' do
      let(:job) { { 'args' => [project.id, non_existing_record_id, 'main', :push, {}] } }

      it 'does not raise an error' do
        expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test')) }
          .not_to raise_error
      end
    end

    context 'when run through Sidekiq::JobRetry', :clean_gitlab_redis_queues do
      let(:retry_handler) { Sidekiq::JobRetry.new(Sidekiq::Capsule.new('test', Sidekiq.default_configuration)) }
      let(:retry_request) { Ci::PipelineCreation::Requests.start_for_ref(project, 'refs/heads/main') }

      def run_failing_job(retry_count)
        job = described_class.get_sidekiq_options.merge(
          'class' => described_class.name, 'args' => [project.id, non_existing_record_id, 'main', 'push', {}, { 'pipeline_creation_request' => retry_request }], 'retry_count' => retry_count
        )

        Gitlab::SidekiqSharding::Validator.allow_unrouted_sidekiq_calls do
          retry_handler.local(described_class.new, job.to_json, described_class.queue) { raise StandardError }
        end
      end

      it 'leaves the request in progress while retries remain' do
        expect { run_failing_job(0) }.to raise_error(Sidekiq::JobRetry::Handled)

        expect(Ci::PipelineCreation::Requests.hget(retry_request)['status']).to eq('in_progress')
      end

      it 'fails the request when the last retry fails' do
        expect { run_failing_job(described_class.get_sidekiq_options['retry'] - 1) }
          .to raise_error(Sidekiq::JobRetry::Handled)

        expect(Ci::PipelineCreation::Requests.hget(retry_request)).to be_nil
      end
    end
  end

  describe '#perform_failure' do
    let_it_be(:project) { create(:project) }

    it 'logs the exception message as the error' do
      exception = RuntimeError.new('something went wrong')

      expect(Sidekiq.logger).to receive(:warn).with(hash_including(
        class: 'CreatePipelineWorker',
        project_id: project.id,
        project_path: project.full_path,
        message: 'Error creating pipeline',
        errors: 'something went wrong'
      ))

      described_class.new.perform_failure(project.id, 'main', exception)
    end

    context 'when project is not found' do
      it 'does not log' do
        expect(Sidekiq.logger).not_to receive(:warn)

        described_class.new.perform_failure(non_existing_record_id, 'main', RuntimeError.new)
      end
    end
  end

  describe '#perform' do
    let(:worker) { described_class.new }
    let_it_be(:project) { create(:project) }
    let(:user) { create(:user) }
    let(:create_pipeline_service) { instance_double(Ci::CreatePipelineService) }
    let(:pipeline) { instance_double(Ci::Pipeline, persisted?: true, project_id: project.id) }
    let(:perform_args) do
      [
        project.id, user.id, project.default_branch, :web,
        { 'save_on_errors' => false }, { 'pipeline_creation_request' => { 'key' => 'test-key' } }
      ]
    end

    shared_examples 'does not call the Service' do
      specify do
        expect(Ci::CreatePipelineService).not_to receive(:new)
        expect { subject }.not_to raise_exception
      end
    end

    context 'when a project not found' do
      subject(:perform) { worker.perform(non_existing_record_id, create(:user).id, 'master', :web) }

      it_behaves_like 'does not call the Service'
    end

    context 'when a user not found' do
      subject(:perform) { worker.perform(project.id, non_existing_record_id, project.default_branch, :web) }

      it_behaves_like 'does not call the Service'
    end

    context 'when everything is ok' do
      let(:service_response) { instance_double(ServiceResponse, payload: pipeline, error?: false) }

      it 'calls the Service' do
        expect(Ci::CreatePipelineService).to receive(:new)
          .with(project, user, ref: project.default_branch, pipeline_creation_request: { 'key' => 'test-key' })
          .and_return(create_pipeline_service)
        expect(create_pipeline_service).to receive(:execute).with(:web, { save_on_errors: false })
                                                            .and_return(service_response)
        expect(worker).not_to receive(:log_pipeline_errors)

        worker.perform(*perform_args)
      end
    end

    context 'when CreatePipelineService responds with an error' do
      let(:service_response) do
        instance_double(ServiceResponse, payload: pipeline, error?: true, message: 'error message')
      end

      before do
        allow(Ci::CreatePipelineService).to receive(:new).and_return(create_pipeline_service)
        allow(create_pipeline_service).to receive(:execute).and_return(service_response)
      end

      it 'logs the error' do
        expect(Ci::CreatePipelineService).to receive(:new)
          .with(project, user, ref: project.default_branch, pipeline_creation_request: { 'key' => 'test-key' })
        expect(create_pipeline_service).to receive(:execute).with(:web, { save_on_errors: false })
        expect(Sidekiq.logger).to receive(:warn).with(hash_including(
          class: 'CreatePipelineWorker',
          project_id: project.id,
          project_path: project.full_path,
          message: 'Error creating pipeline',
          errors: 'error message'
        ))

        worker.perform(*perform_args)
      end
    end

    context 'with a ref pipeline creation request' do
      let_it_be(:project) { create(:project, :repository) }
      let_it_be(:auto_merge_merge_request) do
        create(:merge_request, :merge_when_checks_pass,
          source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let_it_be(:other_merge_request) do
        create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'markdown')
      end

      let(:persisted) { false }
      let(:pipeline) { instance_double(Ci::Pipeline, persisted?: persisted, project_id: project.id) }
      let(:service_response) { instance_double(ServiceResponse, payload: pipeline, error?: false) }
      let(:request) { Ci::PipelineCreation::Requests.start_for_ref(project, 'refs/heads/feature') }
      let(:creation_params) { { 'pipeline_creation_request' => request } }
      let(:perform_args) { [project.id, user.id, 'refs/heads/feature', :push, {}, creation_params] }

      before do
        allow(Ci::CreatePipelineService).to receive(:new).and_return(create_pipeline_service)
        allow(create_pipeline_service).to receive(:execute).and_return(service_response)
        allow(Ci::PipelineCreation::ExperienceReporter).to receive(:report)
      end

      context 'when no pipeline is saved' do
        it 'runs auto-merge for the merge requests from that branch' do
          expect(AutoMergeProcessWorker).to receive(:perform_async)
            .with({ 'merge_request_id' => [auto_merge_merge_request.id] })

          worker.perform(*perform_args)
        end

        context 'when the request is a project request' do
          let(:request) { Ci::PipelineCreation::Requests.start_for_project(project) }

          it 'does not run auto-merge' do
            expect(AutoMergeProcessWorker).not_to receive(:perform_async)

            worker.perform(*perform_args)
          end
        end

        context 'when the job will be retried for a transient Gitaly read' do
          let(:service_response) do
            instance_double(ServiceResponse, payload: pipeline, error?: true,
              message: Gitlab::Ci::Pipeline::Chain::Validate::Repository::REFERENCE_NOT_FOUND_MESSAGE)
          end

          let(:creation_params) do
            { 'before' => Gitlab::Git::SHA1_BLANK_SHA, 'pipeline_creation_request' => request }
          end

          it 'does not run auto-merge' do
            expect(AutoMergeProcessWorker).not_to receive(:perform_async)

            expect { worker.perform(*perform_args) }.to raise_error(described_class::TransientGitalyReadError)
          end
        end

        context 'when the error will not be retried' do
          let(:service_response) do
            instance_double(ServiceResponse, payload: pipeline, error?: true, message: 'error message')
          end

          it 'fails the request before running auto-merge' do
            expect(AutoMergeProcessWorker).to receive(:perform_async) do
              expect(Ci::PipelineCreation::Requests.hget(request)).to be_nil
            end

            worker.perform(*perform_args)
          end

          context 'when the request is a project request' do
            let(:request) { Ci::PipelineCreation::Requests.start_for_project(project) }

            it 'leaves failing the request to the service' do
              expect(Ci::PipelineCreation::Requests).not_to receive(:failed)

              worker.perform(*perform_args)
            end
          end
        end
      end

      context 'when the pipeline is saved' do
        let(:persisted) { true }

        it 'leaves auto-merge to the pipeline' do
          expect(AutoMergeProcessWorker).not_to receive(:perform_async)

          worker.perform(*perform_args)
        end
      end
    end

    context 'when reference not found retry conditions are met' do
      let(:blank_sha) { Gitlab::Git::SHA1_BLANK_SHA }
      let(:ref_not_found_message) { Gitlab::Ci::Pipeline::Chain::Validate::Repository::REFERENCE_NOT_FOUND_MESSAGE }
      let(:service_response) { instance_double(ServiceResponse, error?: true, message: ref_not_found_message, payload: pipeline) }
      let(:push_args) { [project.id, user.id, project.default_branch, :push, {}, { 'before' => blank_sha }] }

      before do
        allow(Ci::CreatePipelineService).to receive(:new).and_return(create_pipeline_service)
        allow(create_pipeline_service).to receive(:execute).and_return(service_response)
      end

      it 'raises TransientGitalyReadError without logging' do
        expect(Sidekiq.logger).not_to receive(:warn)

        expect { worker.perform(*push_args) }
          .to raise_error(described_class::TransientGitalyReadError)
      end

      context 'with a ref pipeline creation request', :clean_gitlab_redis_shared_state do
        let(:request) { Ci::PipelineCreation::Requests.start_for_ref(project, "refs/heads/#{project.default_branch}") }
        let(:push_args) do
          [project.id, user.id, project.default_branch, :push, {},
            { 'before' => blank_sha, 'pipeline_creation_request' => request }]
        end

        it 'leaves the request in progress for the retry' do
          expect(Ci::PipelineCreation::Requests).not_to receive(:failed)

          expect { worker.perform(*push_args) }
            .to raise_error(described_class::TransientGitalyReadError)

          expect(Ci::PipelineCreation::Requests.hget(request)['status'])
            .to eq(Ci::PipelineCreation::Requests::IN_PROGRESS)
        end
      end

      context 'when before SHA is not blank' do
        let(:push_args) do
          [project.id, user.id, project.default_branch, :push, {}, { 'before' => 'abc123def456abc123def456abc123def456abc1' }]
        end

        it 'does not raise and logs the error instead' do
          expect(Sidekiq.logger).to receive(:warn)

          expect { worker.perform(*push_args) }.not_to raise_error
        end
      end

      context 'when error message is not "Reference not found"' do
        let(:service_response) { instance_double(ServiceResponse, error?: true, message: 'some other error', payload: pipeline) }

        it 'does not raise and logs the error instead' do
          expect(Sidekiq.logger).to receive(:warn)

          expect { worker.perform(*push_args) }.not_to raise_error
        end
      end
    end

    context 'when the pipeline creation fails with "Commit not found"' do
      let(:commit_not_found_message) { Gitlab::Ci::Pipeline::Chain::Validate::Repository::COMMIT_NOT_FOUND_MESSAGE }
      let(:service_response) { instance_double(ServiceResponse, error?: true, message: commit_not_found_message, payload: pipeline) }
      let(:before_sha) { 'abc123def456abc123def456abc123def456abc1' }
      let(:push_args) { [project.id, user.id, project.default_branch, :push, {}, { 'before' => before_sha }] }

      before do
        allow(Ci::CreatePipelineService).to receive(:new).and_return(create_pipeline_service)
        allow(create_pipeline_service).to receive(:execute).and_return(service_response)
      end

      it 'raises TransientGitalyReadError without logging, regardless of the before SHA' do
        expect(Sidekiq.logger).not_to receive(:warn)

        expect { worker.perform(*push_args) }
          .to raise_error(described_class::TransientGitalyReadError)
      end

      context 'when before SHA is blank' do
        let(:before_sha) { Gitlab::Git::SHA1_BLANK_SHA }

        it 'raises TransientGitalyReadError without logging' do
          expect(Sidekiq.logger).not_to receive(:warn)

          expect { worker.perform(*push_args) }
            .to raise_error(described_class::TransientGitalyReadError)
        end
      end

      context 'when error message is not "Commit not found"' do
        let(:service_response) { instance_double(ServiceResponse, error?: true, message: 'some other error', payload: pipeline) }

        it 'does not raise and logs the error instead' do
          expect(Sidekiq.logger).to receive(:warn)

          expect { worker.perform(*push_args) }.not_to raise_error
        end
      end

      context 'when ci_create_pipeline_worker_retry_on_commit_not_found feature flag is disabled' do
        before do
          stub_feature_flags(ci_create_pipeline_worker_retry_on_commit_not_found: false)
        end

        it 'does not raise and logs the error instead' do
          expect(Sidekiq.logger).to receive(:warn)

          expect { worker.perform(*push_args) }.not_to raise_error
        end
      end
    end
  end

  describe 'create_pipeline_from_commit user experience' do
    let(:worker) { described_class.new }
    let_it_be(:sli_project) { create(:project) }
    let(:sli_user) { create(:user) }
    let(:started_at) { 3.seconds.ago.to_f }
    let(:pipeline) { instance_double(Ci::Pipeline, persisted?: true) }
    let(:service_response) { instance_double(ServiceResponse, payload: pipeline, error?: false, message: nil) }
    let(:creation_request) { { 'pipeline_creation_request' => { 'started_at' => started_at } } }
    let(:perform_args) { [sli_project.id, sli_user.id, sli_project.default_branch, :push, {}, creation_request] }

    before do
      allow(Ci::CreatePipelineService).to receive(:new)
        .and_return(instance_double(Ci::CreatePipelineService, execute: service_response))
    end

    it 'reports the finished creation with the request start time' do
      expect(Ci::PipelineCreation::ExperienceReporter).to receive(:report)
        .with(pipeline: pipeline, source: :push, started_at: started_at)

      worker.perform(*perform_args)
    end

    # merge_request_event reaches this worker only from the GraphQL pipelineCreate mutation
    # with mergeRequestIid, an API creation outside the SLI.
    %i[merge_request_event api web].each do |source|
      context "when the source is #{source}" do
        let(:perform_args) { [sli_project.id, sli_user.id, sli_project.default_branch, source, {}, creation_request] }

        it 'does not report' do
          expect(Ci::PipelineCreation::ExperienceReporter).not_to receive(:report)

          worker.perform(*perform_args)
        end
      end
    end

    context 'when a retriable transient error is raised' do
      let(:blank_sha) { Gitlab::Git::SHA1_BLANK_SHA }
      let(:ref_not_found) { Gitlab::Ci::Pipeline::Chain::Validate::Repository::REFERENCE_NOT_FOUND_MESSAGE }
      let(:service_response) { instance_double(ServiceResponse, error?: true, message: ref_not_found, payload: pipeline) }
      let(:creation_request) do
        { 'pipeline_creation_request' => { 'key' => 'test-key', 'id' => 'test-id', 'started_at' => started_at } }
      end

      let(:perform_args) do
        [sli_project.id, sli_user.id, sli_project.default_branch, :push, {},
          creation_request.merge('before' => blank_sha)]
      end

      it 'does not report, leaving emission to the successful retry or exhaustion' do
        expect(Ci::PipelineCreation::ExperienceReporter).not_to receive(:report)

        expect { worker.perform(*perform_args) }.to raise_error(described_class::TransientGitalyReadError)
      end
    end

    describe 'when retries are exhausted' do
      let(:exhausted_request) { { 'key' => 'test-key', 'id' => 'test-id', 'started_at' => started_at } }

      let(:job) do
        { 'args' => [sli_project.id, sli_user.id, 'main', 'push', {},
          { 'pipeline_creation_request' => exhausted_request }] }
      end

      it 'reports an errored experience' do
        allow_next_instance_of(described_class) { |w| allow(w).to receive(:perform_failure) }

        expect(Ci::PipelineCreation::ExperienceReporter).to receive(:report_error)
          .with(source: 'push', started_at: started_at, project_id: sli_project.id)

        described_class.sidekiq_retries_exhausted_block.call(job, RuntimeError.new)
      end

      context 'when the source is merge_request_event' do
        let(:job) do
          { 'args' => [sli_project.id, sli_user.id, 'main', 'merge_request_event', {},
            { 'pipeline_creation_request' => exhausted_request }] }
        end

        it 'does not report' do
          allow_next_instance_of(described_class) { |w| allow(w).to receive(:perform_failure) }

          expect(Ci::PipelineCreation::ExperienceReporter).not_to receive(:report_error)

          described_class.sidekiq_retries_exhausted_block.call(job, RuntimeError.new)
        end
      end
    end
  end
end
