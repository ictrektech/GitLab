# frozen_string_literal: true

module Security
  # Recognizes duo_workflow workload pipelines that scanned the default branch (its HEAD
  # now, or its HEAD when the scan was dispatched), letting their security findings
  # ingest into the Vulnerability Report.
  module AgenticAnalyzer
    module_function

    # Set by Ai::DuoWorkflows::StartWorkflowService on the workload job: the branch the
    # workload ref was cut from, resolved at dispatch (default branch when blank or missing).
    SOURCE_BRANCH_VARIABLE = 'DUO_WORKFLOW_SOURCE_BRANCH'

    # Report types the agentic analyzer publishes (see
    # Ai::Catalog::FoundationalFlow#report_artifacts, e.g. { sast: [...] }).
    # Only scans of these types are considered; this does not tell one agentic scan
    # apart from another SAST scan on the same workload pipeline.
    AGENTIC_REPORT_TYPES = %w[sast].freeze

    # We only need the newest workload pipeline(s) at this SHA, so cap the id materialization.
    MAX_WORKLOAD_CANDIDATES = 50

    # Upper bound on the open merge requests re-evaluated after an agentic analyzer scan (newest first).
    MAX_MERGE_REQUESTS_TO_SYNC = 20

    # Upper bound on the scans (and Gitaly ancestry checks) tried when looking for the
    # latest agentic analyzer scan of a branch.
    MAX_BRANCH_SCAN_CANDIDATES = 5

    # Upper bound on the recent workload pipeline ids looked through for those scans. The
    # full-scan filter runs first, so frequent partial (MR) scans do not use up the cap.
    MAX_BRANCH_SCAN_WORKLOADS = 500

    def default_branch_scan?(pipeline)
      project = pipeline.project
      return false unless pipeline.workload? && pipeline.source.to_sym == :duo_workflow && enabled?(project)

      Gitlab::SafeRequestStore.fetch([:agentic_analyzer_default_branch_scan, pipeline.id]) do
        default_sha = project.commit(project.default_branch)&.id

        if default_sha.blank?
          log_default_branch_scan(pipeline, false, 'default_branch_not_found')
          false
        elsif pipeline.sha == default_sha
          true
        else
          source_branch = dispatch_source_branch(pipeline)

          if source_branch.present? && source_branch == project.default_branch
            # pipeline.sha is the default-branch HEAD at dispatch, so a push during a long scan
            # keeps its results, but a SHA a force push rewrote off the default branch does not.
            dispatch_sha_on_default_branch?(pipeline, default_sha)
          else
            reason = source_branch.present? ? 'not_dispatched_for_default_branch' : 'dispatch_branch_unknown'
            log_default_branch_scan(pipeline, false, reason)
            false
          end
        end
      end
    end

    def dispatch_sha_on_default_branch?(pipeline, default_sha)
      on_default_branch = pipeline.project.repository.ancestor?(pipeline.sha, default_sha)
      reason = on_default_branch ? 'default_branch_moved_since_dispatch' : 'dispatch_sha_not_on_default_branch'
      log_default_branch_scan(pipeline, on_default_branch, reason)
      on_default_branch
    end

    # Derived from the workload job's own dispatch-time variables, so no new column is needed.
    # Nil for workloads started before the variable existed.
    def dispatch_source_branch(pipeline)
      pipeline.builds.order_id_asc.first&.yaml_variables&.find do |variable|
        variable[:key].to_s == SOURCE_BRANCH_VARIABLE
      end&.dig(:value)
    end

    def log_default_branch_scan(pipeline, default_branch_scan, reason)
      Gitlab::AppJsonLogger.info(
        Labkit::Fields::CLASS_NAME => name,
        message: 'Agentic analyzer default-branch scan check',
        default_branch_scan: default_branch_scan,
        default_branch_scan_reason: reason,
        Labkit::Fields::GL_PROJECT_ID => pipeline.project_id,
        Labkit::Fields::GL_PIPELINE_ID => pipeline.id
      )
    end

    def scan_marker_key(project_id, sha)
      "#{name}::sast_scan::#{project_id}::#{sha}"
    end

    # Marks project+commit as having an agentic SAST scan, so MR pages for unmarked commits skip the
    # CI lookup. Lives as long as the scan itself (Security::Scan.stale_after). Recorded with the flag
    # off too, so turning it on does not hide scans that were already stored.
    def record_scan(pipeline)
      return unless pipeline.workload? && pipeline.source.to_sym == :duo_workflow

      Gitlab::Redis::SharedState.with do |redis|
        redis.set(scan_marker_key(pipeline.project_id, pipeline.sha), 1, ex: ::Security::Scan.stale_after.to_i)
      end
    end

    # A present marker only means "maybe" (the SQL still decides); an absent one skips the SQL.
    def scan_recorded?(project, sha)
      return false if sha.blank?

      Gitlab::SafeRequestStore.fetch([:agentic_analyzer_scan_recorded, project.id, sha]) do
        Gitlab::Redis::SharedState.with do |redis|
          redis.exists?(scan_marker_key(project.id, sha)) # rubocop:disable CodeReuse/ActiveRecord -- Redis, not AR
        end
      end
    end

    # Callers check this first; for subgroup projects it costs at most one memoized top-level group query.
    # Checked on the top-level group, so one flag actor covers all of a customer's projects.
    def enabled?(project)
      Feature.enabled?(:agentic_analyzer_security_ingestion, project.root_ancestor)
    end

    # Whether `pipeline` or one of its child pipelines ran a successful (latest) scan of
    # `report_type`, whether or not it produced findings.
    def pipeline_has_successful_scan?(pipeline, report_type)
      ::Security::Scan.by_pipeline_ids(pipeline.self_and_project_descendants.pluck_primary_key)
        .by_scan_types(report_type).latest_successful.exists?
    end

    # The latest agentic workload pipeline that scanned `sha` with a successful scan of
    # `report_types`, used to resolve an MR security head pipeline (the base comes from
    # latest_branch_scan_pipeline_for). Resolves the pipeline via the scan's
    # partition-aware loader (no cross-schema re-query).
    def scan_pipeline_for(project, sha, report_types = AGENTIC_REPORT_TYPES)
      latest_agentic_scan(project, sha, report_types)&.pipeline
    end

    # Agentic-analyzer workload pipeline ids at `sha` (succeeded scans): at most the latest full
    # and the latest partial run, so re-runs at one commit are not counted twice and an older
    # run's findings do not linger.
    def scan_pipeline_ids_for(project, sha)
      # rubocop:disable CodeReuse/ActiveRecord -- scoped, per-sha bounded read in security service
      scans = agentic_scans(project, sha).order(pipeline_id: :desc)
      [scans.without_partial_scan, scans.partial].filter_map { |relation| relation.pick(:pipeline_id) }.uniq
      # rubocop:enable CodeReuse/ActiveRecord
    end

    # Whether `pipeline` is a recognized workload pipeline with a succeeded agentic analyzer
    # scan, i.e. one RelatedPipelines includes in approval policy evaluation.
    def scan_pipeline?(pipeline)
      return false unless pipeline.workload? && pipeline.source.to_sym == :duo_workflow

      scan_pipeline_ids_for(pipeline.project, pipeline.sha).include?(pipeline.id)
    end

    # Open merge requests whose latest diff head is `sha`, newest first (indexed on head_commit_sha, bounded).
    def opened_merge_requests_at(project, sha)
      project.merge_requests.opened.with_latest_diff_head_sha(sha)
        .with_order_id_desc.limit(MAX_MERGE_REQUESTS_TO_SYNC)
        .preload_head_pipeline_and_latest_diff # read per MR by diff_head_pipeline
    end

    def latest_agentic_scan(project, sha, report_types = AGENTIC_REPORT_TYPES)
      # rubocop:disable CodeReuse/ActiveRecord -- scoped read in security service
      agentic_scans(project, sha, report_types).order(pipeline_id: :desc).first
      # rubocop:enable CodeReuse/ActiveRecord
    end

    def agentic_scans(project, sha, report_types = AGENTIC_REPORT_TYPES)
      return ::Security::Scan.none unless sha && enabled?(project)

      agentic_scans_in(project, workload_pipeline_ids_at(project, sha), report_types)
    end

    # The latest full (not partial) agentic analyzer scan pipeline of a commit on
    # `branch`: the like-for-like base when comparing an MR that targets `branch`. Scans run
    # on a schedule, so the branch HEAD has usually moved on since the last scan, and an
    # exact-SHA match would miss it and make every pre-existing finding look new.
    def latest_branch_scan_pipeline_for(project, branch)
      return unless enabled?(project)

      branch_sha = project.commit(branch)&.id
      return unless branch_sha

      candidate_ids = ::Ci::Pipeline.recent_source_ids_in_window(project, :duo_workflow,
        limit: MAX_BRANCH_SCAN_WORKLOADS)
      # Filter on full scans first, in one query, so only pipelines with one take the
      # flow lookup. Capped at MAX_WORKLOAD_CANDIDATES to bound that lookup's id lists.
      # rubocop:disable CodeReuse/ActiveRecord -- scoped, bounded read in security service
      scans = agentic_scans_in(project, candidate_ids).without_partial_scan
        .order(pipeline_id: :desc).limit(MAX_WORKLOAD_CANDIDATES).to_a
      # rubocop:enable CodeReuse/ActiveRecord
      bl_pipeline_ids = bl_security_flow_pipeline_ids(scans.map(&:pipeline_id).uniq)
      scans = scans.select { |scan| bl_pipeline_ids.include?(scan.pipeline_id) }
        .uniq(&:pipeline_id).first(MAX_BRANCH_SCAN_CANDIDATES)

      scans.map(&:pipeline).find do |pipeline|
        pipeline.sha == branch_sha || project.repository.ancestor?(pipeline.sha, branch_sha)
      end
    end

    def agentic_scans_in(project, candidate_ids, report_types = AGENTIC_REPORT_TYPES)
      return ::Security::Scan.none if candidate_ids.empty?

      ::Security::Scan
        .by_project(project)
        .by_scan_types(report_types)
        .succeeded
        .latest
        .by_pipeline_ids(candidate_ids)
    end

    # Of the workload pipeline ids, those whose workflow ran the business logic security
    # flow, so a full SAST scan another flow ran is not taken as its base. The tables span
    # the CI and main databases, so each hop is a bounded id lookup instead of a join.
    def bl_security_flow_pipeline_ids(pipeline_ids)
      return [] if pipeline_ids.empty?

      # Each hop is one row per id (a pipeline has one workload, a workload one workflow).
      # rubocop:disable CodeReuse/ActiveRecord -- bounded id lookups in security service
      pipeline_ids_by_workload_id = ::Ci::Workloads::Workload.in_partition(::Ci::Partition.recent_ids)
        .where(pipeline_id: pipeline_ids).limit(pipeline_ids.size).pluck(:id, :pipeline_id).to_h
      workflow_ids_by_workload_id = ::Ai::DuoWorkflows::WorkflowsWorkload
        .where(workload_id: pipeline_ids_by_workload_id.keys).limit(pipeline_ids.size)
        .pluck(:workload_id, :workflow_id).to_h
      bl_workflow_ids = ::Ai::DuoWorkflows::Workflow.id_in(workflow_ids_by_workload_id.values)
        .with_workflow_definition(::Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE)
        .limit(pipeline_ids.size).pluck(:id)
      # rubocop:enable CodeReuse/ActiveRecord

      workflow_ids_by_workload_id.filter_map do |workload_id, workflow_id|
        pipeline_ids_by_workload_id[workload_id] if bl_workflow_ids.include?(workflow_id)
      end
    end

    # Bounded, ordered lookup of duo_workflow pipeline ids (the same source
    # default_branch_scan? requires) at `sha` in the recent CI partitions, newest first.
    def workload_pipeline_ids_at(project, sha)
      Gitlab::SafeRequestStore.fetch([:agentic_workload_pipeline_ids, project.id, sha]) do
        ::Ci::Pipeline.recent_ids_for_sha_and_source(project, sha, :duo_workflow, limit: MAX_WORKLOAD_CANDIDATES)
      end
    end

    # The commit a business logic security scan of `pipeline`'s code would have run on. A
    # merged-results pipeline runs on a temporary merge commit, so use its source commit instead
    # (falling back to its sha), like Security::RelatedPipelinesFinder but only the source commit.
    def scanned_sha(pipeline)
      pipeline.merged_result_pipeline? ? pipeline.source_sha.presence || pipeline.sha : pipeline.sha
    end

    # scan_pipeline_ids_for at the commit `pipeline` scanned (see scanned_sha), so a
    # merged-results pipeline still finds the scan of its source commit.
    def scan_pipeline_ids_for_pipeline(pipeline)
      scan_pipeline_ids_for(pipeline.project, scanned_sha(pipeline))
    end
    private_class_method :dispatch_sha_on_default_branch?, :dispatch_source_branch, :log_default_branch_scan
  end
end
