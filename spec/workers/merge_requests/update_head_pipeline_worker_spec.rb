# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::UpdateHeadPipelineWorker, feature_category: :code_review_workflow do
  include ProjectForksHelper

  let_it_be(:project) { create(:project, :repository) }

  let(:ref) { 'master' }
  let(:pipeline) { create(:ci_pipeline, project: project, ref: ref) }
  let(:pipeline_creation_request) { nil }
  let(:event) do
    event_data = {
      pipeline_id: pipeline.id,
      partition_id: pipeline.partition_id
    }
    event_data[:pipeline_creation_request] = pipeline_creation_request if pipeline_creation_request

    Ci::PipelineCreatedEvent.new(data: event_data)
  end

  subject(:handle_event) { consume_event(subscriber: described_class, event: event) }

  it_behaves_like 'subscribes to event'

  context 'when merge requests already exist for this source branch', :sidekiq_inline do
    let(:merge_request_1) do
      create(:merge_request, source_branch: 'feature', target_branch: "master", source_project: project)
    end

    let(:merge_request_2) do
      create(:merge_request, source_branch: 'feature', target_branch: "v1.1.0", source_project: project)
    end

    context 'when the head pipeline sha equals merge request sha' do
      let(:ref) { 'feature' }

      before do
        pipeline.update!(sha: project.repository.commit(ref).id)
      end

      it 'updates head pipeline of each merge request' do
        merge_request_1
        merge_request_2

        handle_event

        expect(merge_request_1.reload.head_pipeline).to eq(pipeline)
        expect(merge_request_2.reload.head_pipeline).to eq(pipeline)
      end

      context 'when a ref pipeline creation request is included' do
        let(:pipeline_creation_request) { Ci::PipelineCreation::Requests.start_for_ref(project, "refs/heads/#{ref}") }

        it 'completes the request after updating merge request head pipelines' do
          merge_request_1
          merge_request_2

          expect { handle_event }
            .to change { Ci::PipelineCreation::Requests.hget(pipeline_creation_request) }
            .from(a_hash_including('status' => Ci::PipelineCreation::Requests::IN_PROGRESS)).to(nil)

          expect(merge_request_1.reload.head_pipeline).to eq(pipeline)
          expect(merge_request_2.reload.head_pipeline).to eq(pipeline)
        end

        it 'does not trigger GraphQL updates, which only carry merge request requests' do
          merge_request_1
          merge_request_2

          expect(GraphqlTriggers).not_to receive(:ci_pipeline_creation_requests_updated)

          handle_event
        end

        it 'loads the open merge requests once' do
          merge_request_1
          merge_request_2

          recorder = ActiveRecord::QueryRecorder.new { handle_event }
          opened_queries = recorder.log.count do |query|
            query.include?('FROM "merge_requests"') && query.include?('"merge_requests"."state_id"')
          end

          expect(opened_queries).to eq(1)
        end

        context 'when the pipeline is already complete' do
          let(:pipeline) { create(:ci_pipeline, project: project, ref: ref, status: :skipped) }
          let(:merge_request_1) do
            create(:merge_request, :merge_when_checks_pass,
              source_branch: 'feature', target_branch: 'master', source_project: project)
          end

          it 'runs auto-merge for the pipeline once the request is gone' do
            merge_request_1
            merge_request_2

            expect(AutoMergeProcessWorker).to receive(:perform_async).with({ 'pipeline_id' => pipeline.id }) do
              expect(Ci::PipelineCreation::Requests.hget(pipeline_creation_request)).to be_nil
            end

            handle_event
          end

          context 'when no merge request has auto-merge enabled' do
            let(:merge_request_1) do
              create(:merge_request, source_branch: 'feature', target_branch: 'master', source_project: project)
            end

            it 'does not run auto-merge' do
              merge_request_1
              merge_request_2

              expect(AutoMergeProcessWorker).not_to receive(:perform_async)

              handle_event
            end

            context 'when auto-merge is set while the job runs' do
              before do
                allow(Ci::PipelineCreation::Requests).to receive(:succeeded).and_wrap_original do |original, *args|
                  merge_request_1.update_columns(auto_merge_enabled: true)
                  original.call(*args)
                end
              end

              it 'runs auto-merge for the pipeline once the request is gone' do
                merge_request_1
                merge_request_2

                expect(AutoMergeProcessWorker).to receive(:perform_async).with({ 'pipeline_id' => pipeline.id }) do
                  expect(Ci::PipelineCreation::Requests.hget(pipeline_creation_request)).to be_nil
                end

                handle_event
              end
            end
          end
        end

        context 'when the pipeline is not complete' do
          let(:merge_request_1) do
            create(:merge_request, :merge_when_checks_pass,
              source_branch: 'feature', target_branch: 'master', source_project: project)
          end

          it 'leaves auto-merge to the pipeline completing' do
            merge_request_1
            merge_request_2

            expect(AutoMergeProcessWorker).not_to receive(:perform_async)

            handle_event
          end

          context 'when the pipeline completes while the job runs' do
            before do
              allow(Ci::PipelineCreation::Requests).to receive(:succeeded).and_wrap_original do |original, *args|
                Ci::Pipeline.id_in(pipeline.id).update_all(status: 'success')
                original.call(*args)
              end
            end

            it 'runs auto-merge for the pipeline once the request is gone' do
              merge_request_1
              merge_request_2

              expect(AutoMergeProcessWorker).to receive(:perform_async).with({ 'pipeline_id' => pipeline.id }) do
                expect(Ci::PipelineCreation::Requests.hget(pipeline_creation_request)).to be_nil
              end

              handle_event
            end
          end
        end
      end

      context 'when a complete pipeline arrives without a pipeline creation request' do
        let(:pipeline) { create(:ci_pipeline, project: project, ref: ref, status: :skipped) }
        let(:merge_request_1) do
          create(:merge_request, :merge_when_checks_pass,
            source_branch: 'feature', target_branch: 'master', source_project: project)
        end

        it 'does not run auto-merge' do
          merge_request_1
          merge_request_2

          expect(AutoMergeProcessWorker).not_to receive(:perform_async)

          handle_event
        end
      end

      context 'when the merge request is not open' do
        before do
          merge_request_1.close!
        end

        it 'only updates the open merge requests' do
          merge_request_1
          merge_request_2

          handle_event

          expect(merge_request_1.reload.head_pipeline).not_to eq(pipeline)
          expect(merge_request_2.reload.head_pipeline).to eq(pipeline)
        end
      end
    end

    context 'when the head pipeline sha does not equal merge request sha' do
      let(:ref) { 'feature' }

      it 'does not update the head piepeline of MRs' do
        merge_request_1
        merge_request_2

        handle_event

        expect(merge_request_1.reload.head_pipeline).not_to eq(pipeline)
        expect(merge_request_2.reload.head_pipeline).not_to eq(pipeline)
      end
    end

    context 'when there is no pipeline for source branch' do
      it "does not update merge request head pipeline" do
        merge_request = create(
          :merge_request,
          source_branch: 'feature',
          target_branch: "branch_1",
          source_project: project
        )

        handle_event

        expect(merge_request.reload.head_pipeline).not_to eq(pipeline)
      end
    end

    context 'when merge request target project is different from source project' do
      let(:project) { fork_project(target_project, nil, repository: true) }
      let(:target_project) { create(:project, :repository) }
      let(:user) { create(:user) }
      let(:ref) { 'feature' }

      before do
        project.add_developer(user)
        pipeline.update!(sha: project.repository.commit(ref).id)
      end

      it 'updates head pipeline for merge request' do
        merge_request = create(
          :merge_request,
          source_branch: 'feature',
          target_branch: "master",
          source_project: project,
          target_project: target_project
        )

        handle_event

        expect(merge_request.reload.head_pipeline).to eq(pipeline)
      end

      context 'when the request is a merge request pipeline creation request' do
        let(:pipeline) do
          create(:ci_pipeline,
            :merge_request_event,
            project: project,
            ref: merge_request_1.ref_path,
            sha: project.repository.commit(ref).id,
            merge_request: merge_request_1)
        end

        let(:pipeline_creation_request) { Ci::PipelineCreation::Requests.start_for_merge_request(merge_request_1) }

        it 'can complete the pipeline creation request again' do
          handle_event

          request_data = Ci::PipelineCreation::Requests.hget(pipeline_creation_request)

          expect(request_data['status']).to eq(Ci::PipelineCreation::Requests::SUCCEEDED)
          expect(request_data['pipeline_id']).to eq(pipeline.id)
        end
      end
    end

    context 'when the pipeline is not the latest for the branch' do
      it 'does not update merge request head pipeline' do
        merge_request = create(
          :merge_request,
          source_branch: 'master',
          target_branch: "branch_1",
          source_project: project
        )

        create(:ci_pipeline, project: pipeline.project, ref: pipeline.ref)

        handle_event

        expect(merge_request.reload.head_pipeline).to be_nil
      end
    end

    context 'when pipeline has errors' do
      before do
        pipeline.update!(yaml_errors: 'some errors', status: :failed)
      end

      it 'updates merge request head pipeline reference' do
        merge_request = create(
          :merge_request,
          source_branch: 'master',
          target_branch: 'feature',
          source_project: project
        )

        handle_event

        expect(merge_request.reload.head_pipeline).to eq(pipeline)
      end
    end
  end
end
