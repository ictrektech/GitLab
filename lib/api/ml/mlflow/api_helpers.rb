# frozen_string_literal: true

module API
  module Ml
    module Mlflow
      module ApiHelpers
        OUTER_QUOTES_REGEXP = /^("|')|("|')?$/
        GITLAB_TAG_PREFIX = 'gitlab.'

        # LogBatch request limits from https://mlflow.org/docs/latest/api_reference/rest-api.html#log-batch
        MAX_METRICS_PER_BATCH = 1000
        MAX_PARAMS_PER_BATCH = 100
        MAX_TAGS_PER_BATCH = 100
        MAX_ENTITIES_PER_BATCH = 1000
        # GitLab limits: MLflow does not limit the tags of create requests.
        # Registered models and model versions insert one row per tag.
        MAX_TAGS_PER_CREATE_REQUEST = 100
        # Runs and experiments insert all tags in one statement, so they allow the LogBatch total.
        MAX_TAGS_PER_BULK_CREATE_REQUEST = 1000

        def check_api_read!
          not_found! unless can?(current_user, :read_model_experiments, user_project)
        end

        def check_api_write!
          unauthorized! unless can?(current_user, :write_model_experiments, user_project)
        end

        def check_api_model_registry_read!
          not_found! unless can?(current_user, :read_model_registry, user_project)
        end

        def check_api_model_registry_write!
          unauthorized! unless can?(current_user, :write_model_registry, user_project)
        end

        def check_log_batch_limits!
          return unless request_limits_enabled?

          metrics, batch_params, tags = params.values_at(:metrics, :params, :tags).map(&:size)

          check_batch_limit!('metrics', metrics, MAX_METRICS_PER_BATCH)
          check_batch_limit!('params', batch_params, MAX_PARAMS_PER_BATCH)
          check_batch_limit!('tags', tags, MAX_TAGS_PER_BATCH)
          check_batch_limit!('metrics, params, and tags', metrics + batch_params + tags, MAX_ENTITIES_PER_BATCH)
        end

        # Same message as the MLflow tracking server.
        def check_batch_limit!(entity_name, count, limit)
          return if count <= limit

          invalid_parameter!(
            "A batch logging request can contain at most #{limit} #{entity_name}. Got #{count} #{entity_name}. " \
              "Please split up #{entity_name} across multiple requests and try again."
          )
        end

        def check_tags_limit!(limit = MAX_TAGS_PER_CREATE_REQUEST)
          return unless request_limits_enabled?

          count = Array.wrap(params[:tags]).size
          return if count <= limit

          invalid_parameter!("A request can contain at most #{limit} tags. Got #{count} tags.")
        end

        def request_limits_enabled?
          Feature.enabled?(:mlflow_enforce_request_limits, user_project)
        end

        def resource_not_found!
          render_structured_api_error!({ error_code: 'RESOURCE_DOES_NOT_EXIST' }, 404)
        end

        def resource_already_exists!
          render_structured_api_error!({ error_code: 'RESOURCE_ALREADY_EXISTS' }, 400)
        end

        def invalid_parameter!(message = nil)
          render_structured_api_error!({ error_code: 'INVALID_PARAMETER_VALUE', message: message }, 400)
        end

        def update_failed!
          render_structured_api_error!({ error_code: 'UPDATE_FAILED' }, 400)
        end

        # MLflow clients retry 5xx responses. Transient errors return 503 so the client retries the write.
        # Other database errors, including statement timeouts, return 400 so the client does not repeat the query.
        def render_active_record_error!(error)
          # Not user_project: it queries again when the error came from the token or project lookup.
          project = @project # rubocop:disable Gitlab/ModuleWithInstanceVariables -- see the comment above
          return invalid_parameter!(error.message) unless Feature.enabled?(:mlflow_database_error_handling, project)

          case error
          when ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
            invalid_parameter!(error.message)
          when ActiveRecord::RecordNotUnique
            resource_already_exists!
          when ActiveRecord::NotNullViolation, ActiveRecord::ValueTooLong, ActiveRecord::RangeError,
            ->(e) { e.cause.is_a?(PG::CheckViolation) }
            invalid_parameter!('A parameter value is missing, too long, or out of range')
          when ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed, ActiveRecord::Deadlocked,
            ActiveRecord::SerializationFailure, ActiveRecord::LockWaitTimeout
            render_tracked_database_error!(error, 'TEMPORARILY_UNAVAILABLE', 'Temporary database error', 503)
          else
            message = error.is_a?(ActiveRecord::QueryCanceled) ? 'Request timed out' : 'Database error'
            render_tracked_database_error!(error, 'BAD_REQUEST', message, 400)
          end
        end

        def render_tracked_database_error!(error, error_code, message, status)
          Gitlab::ErrorTracking.track_exception(error)
          env[::API::Helpers::API_EXCEPTION_ENV] = error

          render_structured_api_error!({ error_code: error_code, message: message }, status)
        end

        def experiment_repository
          ::Ml::ExperimentTracking::ExperimentRepository.new(user_project, current_user)
        end

        def candidate_repository
          ::Ml::ExperimentTracking::CandidateRepository.new(user_project, current_user)
        end

        def experiment
          @experiment ||= find_experiment!(params[:experiment_id], params[:experiment_name])
        end

        def candidate
          @candidate ||= find_candidate!(params[:run_id])
        end

        def candidates_order_params(params)
          find_params = {
            order_by: nil,
            order_by_type: nil,
            sort: nil
          }

          return find_params if params[:order_by].blank?

          order_by_split = params[:order_by].split(' ')
          order_by_column_split = order_by_split[0].split('.')
          if order_by_column_split.size == 1
            order_by_column = order_by_column_split[0]
            order_by_column_type = 'column'
          elsif order_by_column_split[0] == 'metrics'
            order_by_column = order_by_column_split[1]
            order_by_column_type = 'metric'
          else
            order_by_column = nil
            order_by_column_type = nil
          end

          order_by_sort = order_by_split[1]

          {
            order_by: order_by_column,
            order_by_type: order_by_column_type,
            sort: order_by_sort
          }
        end

        def model_order_params(params)
          if params[:order_by].blank?
            order_by = 'name'
            sort = 'asc'
          else
            order_by, sort = params[:order_by].downcase.split(' ')
            order_by = 'updated_at' if order_by == 'last_updated_timestamp'
            sort ||= 'asc'
          end

          {
            order_by: order_by,
            sort: sort
          }
        end

        def model_filter_params(params)
          return {} if params[:filter].blank?

          param, filter = params[:filter].split('=')

          return {} unless param == 'name'

          filter.gsub!(OUTER_QUOTES_REGEXP, '') unless filter.blank?

          { name: filter }
        end

        def gitlab_tags
          return unless params[:tags].present?

          tags = params[:tags]
          gitlab_params = {}

          tags.each do |tag|
            key, value = tag.values_at(:key, :value)

            gitlab_params[key.delete_prefix(GITLAB_TAG_PREFIX)] = value if key&.starts_with?(GITLAB_TAG_PREFIX)
          end

          gitlab_params
        end

        def custom_version
          return unless gitlab_tags

          gitlab_tags['version']
        end

        def find_experiment!(iid, name)
          experiment_repository.by_iid_or_name(iid: iid, name: name) || resource_not_found!
        end

        def find_candidate!(eid)
          candidate_repository.by_eid(eid) || resource_not_found!
        end

        def find_model(project, name)
          ::Ml::FindModelService.new(project, name).execute || resource_not_found!
        end

        def find_model_version(project, name, version)
          ::Ml::ModelVersions::GetModelVersionService.new(project, name, version).execute || resource_not_found!
        end

        def find_model_artifact(project, version, file_path)
          package = ::Ml::ModelVersion.by_project_id_and_id(project, version)&.package
          resource_not_found! unless package

          ::Packages::PackageFileFinder.new(package, file_path).execute || resource_not_found!
        end

        def find_run_artifact(project, version, file_path)
          package = ::Ml::Candidate.with_project_id_and_iid(project, version)&.package
          resource_not_found! unless package

          ::Packages::PackageFileFinder.new(package, file_path).execute || resource_not_found!
        end

        def list_model_artifacts(project, version)
          model_version = ::Ml::ModelVersion.by_project_id_and_id(project, version)
          resource_not_found! unless model_version && model_version.package

          model_version.package.installable_package_files
        end

        def list_run_artifacts(project, version)
          run = ::Ml::Candidate.with_project_id_and_iid(project, version)

          resource_not_found! unless run&.package

          run.package.installable_package_files
        end

        def model
          @model ||= find_model(user_project, params[:name])
        end

        def bounded_list_responses?
          Feature.enabled?(:mlflow_bounded_list_responses, user_project)
        end

        # experiments/list orders by id only and pages forward, so its cursor holds a bigint id and `_kd: 'n'`.
        def valid_experiments_page_token?(token)
          return true if token.blank?

          attributes = Gitlab::Json.safe_parse(Base64.urlsafe_decode64(token))
          return false unless attributes.is_a?(Hash) && attributes.keys.sort == %w[_kd id]

          id = attributes['id'].to_s
          attributes['_kd'] == Gitlab::Pagination::Keyset::Paginator::FORWARD_DIRECTION &&
            id.match?(/\A\d+\z/) && id.to_i <= Gitlab::Database::MAX_BIGINT_VALUE
        rescue ArgumentError, JSON::ParserError
          false
        end

        def preload_registered_models(models, latest_version_only:)
          versions = latest_version_only ? :latest_version : :versions

          ActiveRecord::Associations::Preloader.new(
            records: Array.wrap(models), associations: [:metadata, { versions => [:metadata, :candidate] }]
          ).call
        end

        def candidate_version?(model_version)
          return false unless model_version

          model_version&.start_with?('candidate:')
        end
      end
    end
  end
end
