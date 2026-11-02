# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::SyncProjectPreexistingStatesApprovalRulesWorker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project, :repository) }
  let(:per_mr_worker) { Security::ScanResultPolicies::SyncPreexistingStatesApprovalRulesWorker }
  let(:newly_detected_worker) { Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker }
  let_it_be(:head_pipeline) do
    create(:ci_pipeline, :success, project: project, ref: 'feature', sha: project.commit('feature').sha,
      finished_at: Time.current)
  end

  let_it_be(:open_mr_with_rule) do
    create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master',
      head_pipeline: head_pipeline)
  end

  let_it_be(:open_mr_without_rule) do
    create(:merge_request, source_project: project, source_branch: 'feature-b', target_branch: 'master')
  end

  let_it_be(:closed_mr_with_rule) do
    create(:merge_request, :closed, source_project: project, source_branch: 'feature-c', target_branch: 'master')
  end

  let_it_be(:other_project_mr_with_rule) { create(:merge_request) }

  before_all do
    create(:security_policy_project_link, project: project)
    create(:report_approver_rule, :scan_finding, merge_request: open_mr_with_rule)
    create(:report_approver_rule, :scan_finding, merge_request: closed_mr_with_rule)
    create(:report_approver_rule, :scan_finding, merge_request: other_project_mr_with_rule)
  end

  describe '#perform' do
    subject(:run_worker) { described_class.new.perform(project_id) }

    let(:project_id) { project.id }

    it 'enqueues the per-merge-request worker for open MRs in the project with scan_finding rules' do
      expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id).once

      run_worker
    end

    it 'does not enqueue for MRs without applicable rules, closed MRs, or MRs in other projects' do
      allow(per_mr_worker).to receive(:perform_async)

      run_worker

      expect(per_mr_worker).not_to have_received(:perform_async).with(open_mr_without_rule.id)
      expect(per_mr_worker).not_to have_received(:perform_async).with(closed_mr_with_rule.id)
      expect(per_mr_worker).not_to have_received(:perform_async).with(other_project_mr_with_rule.id)
    end

    it 'enqueues the newly-detected states sync for open MRs with scan_finding rules against their head pipeline' do
      expect(newly_detected_worker).to receive(:perform_async)
        .with(head_pipeline.id, open_mr_with_rule.id).once

      run_worker
    end

    context 'when the merge request has no pipeline for its diff head' do
      before do
        MergeRequest.id_in(open_mr_with_rule.id).update_all(head_pipeline_id: nil)
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
        expect(newly_detected_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the head pipeline is still running' do
      before do
        Ci::Pipeline.id_in(head_pipeline.id).update_all(status: 'running')
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
        expect(newly_detected_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the head pipeline reports are still being ingested' do
      shared_examples 'skips the newly-detected states sync' do
        it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
          expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
          expect(newly_detected_worker).not_to receive(:perform_async)

          run_worker
        end
      end

      context 'when no scan is stored yet' do
        before do
          build = create(:ee_ci_build, :success, pipeline: head_pipeline, project: project)
          create(:ee_ci_job_artifact, :sast, job: build, project: project)
        end

        it_behaves_like 'skips the newly-detected states sync'
      end

      context 'when a scan is processing' do
        before do
          create(:security_scan, latest: true, status: :created, pipeline: head_pipeline, project: project)
        end

        it_behaves_like 'skips the newly-detected states sync'

        context 'when the head pipeline is blocked on a manual job' do
          before do
            Ci::Pipeline.id_in(head_pipeline.id).update_all(status: 'manual', finished_at: nil)
          end

          it_behaves_like 'skips the newly-detected states sync'
        end

        context 'when the head pipeline finished longer ago than the ingestion wait' do
          let(:max_wait) { Security::ScanResultPolicies::UnblockPendingMergeRequestViolationsWorker::MAX_INGESTION_WAIT }

          before do
            Ci::Pipeline.id_in(head_pipeline.id).update_all(finished_at: (max_wait + 1.minute).ago)
          end

          it 'enqueues the newly-detected states sync' do
            expect(newly_detected_worker).to receive(:perform_async).with(head_pipeline.id, open_mr_with_rule.id)

            run_worker
          end
        end
      end
    end

    context 'when the head pipeline reports are ingested' do
      before do
        create(:security_scan, :latest_successful, pipeline: head_pipeline, project: project)
      end

      it 'enqueues the newly-detected states sync' do
        expect(newly_detected_worker).to receive(:perform_async).with(head_pipeline.id, open_mr_with_rule.id)

        run_worker
      end
    end

    context 'when reevaluate_newly_detected_states_on_vulnerability_triage is disabled' do
      before do
        stub_feature_flags(reevaluate_newly_detected_states_on_vulnerability_triage: false)
      end

      it 'does not enqueue the newly-detected states sync but still enqueues the pre-existing states sync' do
        expect(per_mr_worker).to receive(:perform_async).with(open_mr_with_rule.id)
        expect(newly_detected_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the project does not exist' do
      let(:project_id) { non_existing_record_id }

      it 'does nothing' do
        expect(per_mr_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    context 'when the project has no approval policy' do
      let_it_be(:project_without_policy) { create(:project) }
      let_it_be(:mr_with_rule) do
        create(:merge_request, source_project: project_without_policy, source_branch: 'x', target_branch: 'master')
      end

      let(:project_id) { project_without_policy.id }

      before_all do
        create(:report_approver_rule, :scan_finding, merge_request: mr_with_rule)
      end

      it 'returns early without enqueueing per-merge-request workers' do
        expect(per_mr_worker).not_to receive(:perform_async)

        run_worker
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [project.id] }
    end
  end
end
