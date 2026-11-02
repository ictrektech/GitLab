# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SyncFindingsToApprovalRulesService, feature_category: :security_policy_management do
  include Ci::SourcePipelineHelpers

  let_it_be_with_reload(:project) { create(:project, :repository) }
  let_it_be_with_refind(:merge_request) { create(:merge_request, source_project: project) }

  let_it_be(:target_pipeline) { create(:ee_ci_pipeline, project: project, ref: merge_request.target_branch) }
  let_it_be(:pipeline) do
    create(:ee_ci_pipeline, :success,
      project: project,
      ref: merge_request.source_branch,
      sha: project.commit(merge_request.source_branch).sha,
      merge_requests_as_head_pipeline: [merge_request]
    )
  end

  shared_examples 'updates approvals' do
    it do
      expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker).to receive(:perform_async).with(
        pipeline.id,
        merge_request.id
      ).and_call_original

      execute
    end
  end

  shared_examples 'does not update approvals' do
    it do
      expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker).not_to receive(:perform_async)

      execute
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.new(pipeline).execute }

    context 'when pipeline_findings is empty' do
      it_behaves_like 'updates approvals'
    end

    context 'when pipeline is not complete' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :running, project: project) }

      it_behaves_like 'does not update approvals'
    end

    context 'when pipeline is in manual state' do
      let_it_be_with_refind(:pipeline) { create(:ee_ci_pipeline, :blocked, project: project) }

      it_behaves_like 'updates approvals'
    end

    context 'when pipeline source is not one of ci_and_security_orchestration_sources' do
      let_it_be(:pipeline) { create(:ee_ci_pipeline, :success, project: project, source: :webide) }

      it_behaves_like 'does not update approvals'
    end

    context 'when pipeline source is pipeline_execution_policy_schedule' do
      let_it_be(:pipeline) do
        create(:ee_ci_pipeline, :success,
          project: project,
          ref: merge_request.source_branch,
          sha: project.commit(merge_request.source_branch).sha,
          source: :pipeline_execution_policy_schedule,
          merge_requests_as_head_pipeline: [merge_request]
        )
      end

      it_behaves_like 'updates approvals'
    end

    context 'when pipeline_findings is not empty' do
      let_it_be(:pipeline_scan) { create(:security_scan, project: project, pipeline: pipeline, status: :succeeded) }
      let_it_be(:pipeline_findings) do
        create(:security_finding, scan: pipeline_scan, severity: 'high')
      end

      it_behaves_like 'updates approvals'

      context 'when merge_request is closed' do
        before do
          merge_request.update!(state_id: MergeRequest.available_states[:closed])
        end

        it_behaves_like 'does not update approvals'
      end

      context 'when pipeline is for diff_head_sha' do
        it_behaves_like 'updates approvals'
      end

      context 'when pipeline is not for diff_head_sha' do
        let_it_be(:pipeline) do
          create(:ee_ci_pipeline, :success, project: project, ref: merge_request.source_branch, sha: 'test',
            source_sha: 'test')
        end

        it_behaves_like 'does not update approvals'
      end

      context 'with merge request targeting pipeline ref' do
        let_it_be_with_reload(:other_merge_request) do
          create(
            :merge_request,
            source_project: project,
            target_branch: merge_request.source_branch,
            source_branch: "feature")
        end

        let_it_be_with_reload(:other_pipeline) do
          create(
            :ee_ci_pipeline,
            project: project,
            ref: other_merge_request.source_branch,
            sha: project.commit(other_merge_request.source_branch).sha,
            merge_requests_as_head_pipeline: [other_merge_request])
        end

        it 'updates approvals for merge requests targeting the source branch' do
          expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker).to receive(:perform_async).with(
            pipeline.id,
            merge_request.id
          ).and_call_original.ordered

          expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker).to receive(:perform_async).with(
            other_pipeline.id,
            other_merge_request.id
          ).and_call_original.ordered

          execute
        end
      end
    end

    context 'when pipeline is an agentic analyzer scan workload pipeline' do
      let(:workload_ref) { 'refs/workloads/abc123' }
      let(:workload_sha) { pipeline.sha }
      let(:scan_status) { :succeeded }
      let(:workload_pipeline) do
        create(:ci_pipeline, :success, project: project, ref: workload_ref, sha: workload_sha, source: :duo_workflow)
      end

      subject(:execute) { described_class.new(workload_pipeline).execute }

      before do
        create(:security_scan, scan_type: :sast, status: scan_status, latest: true,
          build: create(:ci_build, :success, pipeline: workload_pipeline, project: project))
      end

      context 'when it finishes after the merge request head pipeline' do
        it_behaves_like 'updates approvals'
      end

      context 'when agentic_analyzer_security_ingestion is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it_behaves_like 'does not update approvals'
      end

      context 'when the pipeline is not a workload pipeline' do
        let(:workload_ref) { merge_request.source_branch }

        it_behaves_like 'does not update approvals'
      end

      context 'when no open merge request has the scanned sha as its head' do
        let(:workload_sha) { 'a' * 40 }

        it_behaves_like 'does not update approvals'
      end

      context 'when the merge request is closed' do
        before do
          merge_request.close!
        end

        it_behaves_like 'does not update approvals'
      end

      context 'when the scan failed' do
        let(:scan_status) { :job_failed }

        it_behaves_like 'does not update approvals'
      end

      context 'when the merge request has no head pipeline' do
        before do
          merge_request.update_column(:head_pipeline_id, nil)
        end

        it_behaves_like 'does not update approvals'
      end

      context 'when the head pipeline ran on an older commit' do
        before do
          stale_pipeline = create(:ee_ci_pipeline, :success, project: project,
            ref: merge_request.source_branch, sha: 'b' * 40)
          merge_request.update_column(:head_pipeline_id, stale_pipeline.id)
        end

        it_behaves_like 'does not update approvals'
      end

      context 'when the head pipeline is running' do
        before do
          Ci::Pipeline.id_in(pipeline.id).update_all(status: 'running')
        end

        context 'without security findings' do
          it_behaves_like 'does not update approvals'
        end

        context 'with security findings' do
          before do
            create(:security_finding, scan: create(:security_scan, project: project, pipeline: pipeline,
              status: :succeeded))
          end

          it_behaves_like 'updates approvals'
        end
      end

      it 'syncs each merge request at the scanned sha with its own head pipeline' do
        other_merge_request = create(:merge_request, source_project: project, target_branch: 'fix')
        other_pipeline = create(:ee_ci_pipeline, :success, project: project, ref: other_merge_request.source_branch,
          sha: workload_sha, merge_requests_as_head_pipeline: [other_merge_request])

        expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker)
          .to receive(:perform_async).with(pipeline.id, merge_request.id)
        expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker)
          .to receive(:perform_async).with(other_pipeline.id, other_merge_request.id)

        execute
      end

      context 'when the head pipeline is a merged-results pipeline' do
        let(:merged_result_pipeline) do
          create(:ee_ci_pipeline, :success, :merged_result_pipeline, project: project, merge_request: merge_request)
        end

        before do
          merge_request.update_column(:head_pipeline_id, merged_result_pipeline.id)
        end

        it 'syncs it, and the sync finds the scan of its source commit' do
          expect(merged_result_pipeline.source_sha).to eq(workload_sha)
          expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker)
            .to receive(:perform_async).with(merged_result_pipeline.id, merge_request.id)

          execute

          expect(Security::AgenticAnalyzer.scan_pipeline_ids_for_pipeline(merged_result_pipeline))
            .to contain_exactly(workload_pipeline.id)
        end
      end

      it 'syncs only the newest merge requests up to the cap' do
        stub_const('Security::AgenticAnalyzer::MAX_MERGE_REQUESTS_TO_SYNC', 1)
        newer = create(:merge_request, source_project: project, target_branch: 'fix', head_pipeline: pipeline)

        expect(Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker)
          .to receive(:perform_async).once.with(pipeline.id, newer.id)

        execute
      end
    end

    context 'when pipeline is a child pipeline' do
      let_it_be(:child_pipeline) { create(:ci_pipeline, project: project, source: :parent_pipeline) }

      subject(:execute) { described_class.new(child_pipeline).execute }

      before do
        create_source_pipeline(pipeline, child_pipeline)
      end

      context 'when both parent and child pipeline does not have security_findings that violate policy' do
        it_behaves_like 'updates approvals'
      end

      context 'when child_pipeline has security_findings that violate policy' do
        let_it_be(:pipeline_scan) do
          create(:security_scan, project: project, pipeline: child_pipeline, status: :succeeded)
        end

        let_it_be(:pipeline_findings) do
          create(:security_finding, scan: pipeline_scan, severity: 'high')
        end

        it_behaves_like 'updates approvals'
      end

      context 'when parent_pipeline has security_findings that violate policy' do
        let_it_be(:pipeline_scan) do
          create(:security_scan, project: project, pipeline: pipeline, status: :succeeded)
        end

        let_it_be(:pipeline_findings) do
          create(:security_finding, scan: pipeline_scan, severity: 'high')
        end

        it_behaves_like 'updates approvals'
      end
    end
  end
end
