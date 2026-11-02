# frozen_string_literal: true

module Security
  module ScanResultPolicies
    class UnblockPendingMergeRequestViolationsWorker
      include ApplicationWorker
      include Gitlab::Utils::StrongMemoize
      include ::Security::ScanResultPolicies::PolicyLogger

      idempotent!
      data_consistency :sticky
      deduplicate :until_executing, including_scheduled: true
      feature_category :security_policy_management

      # Upper bound on waiting for report ingestion, so reports that are never ingested still unblock.
      MAX_INGESTION_WAIT = 10.minutes

      def perform(pipeline_id)
        pipeline = ::Ci::Pipeline.find_by_id(pipeline_id) || return
        return if rescheduled_until_evaluation_window_elapses?(pipeline)

        pipeline.opened_merge_requests_with_head_sha.each do |merge_request|
          next unless policy_available?(merge_request.target_project)
          next if other_head_pipeline_running?(pipeline, merge_request)

          skip_policy_evaluation(pipeline, merge_request)
        end
      end

      private

      # The head pipeline's own completion schedules its own timeout.
      def other_head_pipeline_running?(pipeline, merge_request)
        return false unless Feature.enabled?(:policy_timeout_waits_for_running_head_pipeline,
          merge_request.target_project)

        head_pipeline = merge_request.diff_head_pipeline
        head_pipeline.present? && head_pipeline.id != pipeline.id && head_pipeline.active?
      end

      # The timeout is scheduled on pipeline completion, but scan_finding rules can only be
      # evaluated once reports are ingested, so the window restarts when ingestion finishes.
      def rescheduled_until_evaluation_window_elapses?(pipeline)
        # Pipelines blocked on manual jobs have no finished_at; updated_at approximates when they became manual.
        completed_at = pipeline.manual? ? pipeline.updated_at : pipeline.finished_at
        return false if completed_at.nil? || completed_at < MAX_INGESTION_WAIT.ago

        delay = remaining_evaluation_window(pipeline)
        return false unless delay&.positive?

        self.class.perform_in(delay, pipeline.id)
        true
      end

      def remaining_evaluation_window(pipeline)
        scans = latest_scans(pipeline)
        return evaluation_timeout if ::Security::Scan.ingestion_pending?(pipeline, scans)

        ingested_at = scans.maximum(:updated_at)
        return unless ingested_at

        ingested_at + evaluation_timeout - Time.current
      end

      def latest_scans(pipeline)
        strong_memoize_with(:latest_scans, pipeline.id) do
          ::Security::Scan.latest_in_hierarchy(pipeline)
        end
      end

      def evaluation_timeout
        ::Security::UnenforceablePolicyRulesPipelineNotificationWorker::UNBLOCK_PENDING_VIOLATIONS_TIMEOUT
      end

      # Memoized per project: an unlicensed project falls through to the dependency
      # firewall check, which is the most expensive branch and would otherwise repeat
      # for every merge request sharing a target.
      def policy_available?(project)
        strong_memoize_with(:policy_available, project.id) do
          ::Security::PolicyAvailability.any_available?(project)
        end
      end

      def skip_policy_evaluation(pipeline, merge_request)
        violations = merge_request.running_scan_result_policy_violations
        return if violations.blank?

        approval_rules = merge_request.approval_rules.report_approver
                                      .for_approval_policy_rules(violations.map(&:approval_policy_rule_id))
        return if approval_rules.blank?

        evaluation = Security::SecurityOrchestrationPolicies::PolicyRuleEvaluationService.new(merge_request)
        approval_rules.each { |rule| evaluation.skip!(rule) }
        evaluation.save
        log_policy_evaluation('unblock_pending_violations',
          'Policy evaluation timed out, skipping and requiring approvals',
          project: merge_request.target_project, merge_request_id: merge_request.id,
          approval_rules: approval_rules)

        reevaluate(pipeline, merge_request)
      end

      # Skipping fails closed, but nothing re-runs a lost evaluation, so the merge
      # request could stay blocked although its reports have no new findings.
      def reevaluate(pipeline, merge_request)
        # A running pipeline skips the scan presence checks; its completion re-evaluates.
        return unless pipeline.complete_or_manual?
        # Evaluating before ingestion sees no findings; ReportsIngestedEvent triggers it instead.
        return if reports_ingestion_pending?(pipeline)

        ::Security::ScanResultPolicies::SyncMergeRequestApprovalsWorker.perform_async(pipeline.id, merge_request.id)
      end

      def reports_ingestion_pending?(pipeline)
        strong_memoize_with(:reports_ingestion_pending, pipeline.id) do
          ::Security::Scan.ingestion_pending?(pipeline, latest_scans(pipeline))
        end
      end
    end
  end
end
