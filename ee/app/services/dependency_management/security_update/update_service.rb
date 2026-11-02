# frozen_string_literal: true

module DependencyManagement
  module SecurityUpdate
    UpdateServiceError = Class.new(StandardError)

    class UpdateService < BaseService
      include Gitlab::Utils::StrongMemoize
      include Gitlab::Loggable

      ORCHESTRATOR_IMAGE = 'registry.gitlab.com/security-products/dependency-management/orchestrator:0'

      SERVICES = %w[docker:28-dind].freeze

      ARTIFACT_PATHS = %w[output.json].freeze

      # Written inside the orchestrator container's /tmp dir - safe because
      # the container is single-use and discarded after the job completes.
      JOB_FILE_PATH = '/tmp/dependency-update-job.json'

      BRANCH_PREFIX = 'dependency-management'

      # @param request [DependencyManagement::SecurityUpdate::Request]
      # @return [ServiceResponse]
      def execute(request)
        return error_response(message: 'Automated dependency security updates not enabled') unless valid?
        return error_response(message: 'Security Update Request not found') unless request

        @request = request
        start_workload.tap { |response| log_workload(response) }
      end

      private

      attr_reader :request

      delegate :source_ref, :target_ref, to: :request, private: true

      def start_workload
        unless workload_ref_refresh?
          create_or_update_source_branch
          return create_workload(ref: source_ref)
        end

        # The workload runs on a hidden ref at the target, so the remediation branch is left as it
        # is until CreateMergeRequestService writes the result.
        create_workload_on_hidden_ref
      end

      # Once the hidden ref is deleted, this line is the only link from a branch to its workload.
      def log_workload(response)
        payload = { Labkit::Fields::GL_PROJECT_ID => project.id, source_branch: source_ref }

        if response.success?
          pipeline = response.payload[:pipeline]
          Gitlab::AppLogger.info(build_structured_payload_labkit(
            message: 'DependencyManagement: started an auto-remediation workload',
            Labkit::Fields::GL_PIPELINE_ID => pipeline.id, workload_ref: pipeline.ref, **payload
          ))
        else
          Gitlab::AppLogger.error(build_structured_payload_labkit(
            message: 'DependencyManagement: failed to start an auto-remediation workload',
            Labkit::Fields::ERROR_MESSAGE => response.message, **payload
          ))
        end
      end

      def valid?
        project.can_store_security_reports?
      end

      # Idempotently create the source branch to use for the update.
      # If the branch doesn't exist, creates it from the target ref.
      # If the branch exists, resets it to the target ref to ensure a clean state.
      def create_or_update_source_branch
        target_sha = project.repository.commit(target_ref)&.sha
        return unless target_sha

        if project.repository.branch_exists?(source_ref)
          reset_branch_to_target(target_sha)
        else
          create_branch_from_target
        end
      end

      def reset_branch_to_target(target_sha)
        current_sha = project.repository.commit(source_ref)&.sha
        return if current_sha == target_sha

        project.repository.update_branch(source_ref, user: service_account, newrev: target_sha, oldrev: current_sha)
      end

      def create_branch_from_target
        project.repository.add_branch(service_account, source_ref, target_ref)
      end

      def workload_ref_refresh?
        Feature.enabled?(:dependency_management_workload_ref_refresh, project)
      end

      # The ref is passed to RunWorkloadService unchanged, so Ci::Workloads::Workload#cleanup_refs
      # removes it once the pipeline finishes.
      def create_workload_on_hidden_ref
        return error_response(message: 'Failed to retrieve or create bot user') unless service_account

        ref_response = Ci::Workloads::WorkloadBranchService
          .new(project: project, source_branch: target_ref, current_user: service_account)
          .execute
        return error_response(message: ref_response.message) unless ref_response.success?

        workload_ref = ref_response.payload[:ref]
        response = create_workload(ref: workload_ref)
        # Without a workload record nothing else removes the ref.
        delete_workload_ref(workload_ref) if response.error?

        response
      rescue StandardError
        delete_workload_ref(workload_ref) if workload_ref
        raise
      end

      def delete_workload_ref(workload_ref)
        project.repository.delete_refs(workload_ref)
      rescue StandardError => e
        log_error(e)
      end

      def create_workload(ref:)
        return error_response(message: 'Failed to retrieve or create bot user') unless service_account

        service = Ci::Workloads::RunWorkloadService.new(
          project: project,
          current_user: service_account,
          source: :dependency_management_security_update,
          workload_definition: build_workload_definition,
          ref: ref
        )

        response = service.execute
        return error_response(message: response.message) unless response.success?

        success_response(payload: { pipeline: response.payload.pipeline })
      end

      def build_workload_definition
        job_json = JobBuilder.new(
          request: request,
          project: project,
          auto_remediation_configuration: auto_remediation_configuration
        ).to_json

        Ci::Workloads::WorkloadDefinition.new do |definition|
          definition.services = SERVICES
          definition.image = ORCHESTRATOR_IMAGE
          definition.commands = build_commands(job_json)
          definition.variables = build_variables
          definition.tags = auto_remediation_configuration[:runner_tags]
          # Expose output.json so CreateMergeRequestService can read
          # the updated file contents and dependency version changes.
          definition.artifacts_paths = ARTIFACT_PATHS
        end
      end

      def build_commands(job_json)
        [
          "echo #{Shellwords.shellescape(job_json)} > #{JOB_FILE_PATH}",
          "dependency-management-orchestrator update --job-file #{JOB_FILE_PATH}"
        ]
      end

      def build_variables
        {
          'DEPENDENCY_MANAGEMENT_PROJECT_PATH' => project.full_path,
          'DEPENDENCY_MANAGEMENT_SOURCE_REF' => source_ref,
          'DEPENDENCY_MANAGEMENT_TARGET_REF' => target_ref,
          'DEPENDENCY_MANAGEMENT_VULNERABILITY_ID' => request.vulnerability.id.to_s,
          'DEPENDENCY_MANAGEMENT_SBOM_OCCURRENCE_ID' => request.sbom_occurrence.id.to_s,
          'DOCKER_HOST' => 'tcp://docker:2376',
          'DOCKER_TLS_CERTDIR' => '/certs'
        }
      end

      # Both callers of this service (SchedulerService and the user-triggered
      # AutoRemediation mutation) already gate on a remediation profile being
      # present, so it is safe to look it up again here.
      def auto_remediation_configuration
        Eligibility.remediation_configuration(project).fetch(:auto_remediation, {})
      end
      strong_memoize_attr :auto_remediation_configuration

      def service_account
        result = DependencyManagement::ProvisionServiceAccountService
          .new(project: project)
          .execute

        unless result.success?
          log_error(UpdateServiceError.new(result.message))
          return
        end

        result.payload[:user]
      end
      strong_memoize_attr :service_account
    end
  end
end
