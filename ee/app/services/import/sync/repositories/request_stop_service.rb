# frozen_string_literal: true

module Import
  module Sync
    module Repositories
      # Starts the stop of GitHub updates: fences every older job, requests one final pass for each data domain and
      # keeps the project read-only until FinishStopWorker has made GitLab the source of truth. A running import
      # must finish first; a failed or canceled one can stop, since the stop is its only way out of read-only.
      class RequestStopService
        include ::Gitlab::InternalEventsTracking

        ConnectionLostError = Class.new(StandardError)
        InvalidStateError = Class.new(StandardError)

        def initialize(repository, requested_at: Time.current)
          @repository = repository
          @requested_at = requested_at
        end

        # Returns the new application generation, or the current one when the stop was already requested. Call it
        # outside a database transaction: the application lease cannot be taken inside one.
        def execute
          previous_state = nil

          generation = ApplicationLease.new(repository.id).execute do |lease_context|
            repository.with_lock do
              validate_connection!
              next repository.application_generation if repository.cutting_over?

              validate_authority!
              validate_import_not_running!
              previous_state = repository.authority_state
              lease_context.verify_repository!(repository.id)
              repository.update!(
                application_generation: repository.application_generation + 1,
                authority_state: :cutting_over,
                cutover_requested_at: requested_at,
                cutover_completed_at: nil
              )
              request_final_domains!
              repository.application_generation
            end
          end

          if previous_state
            log_transition(previous_state, generation)
            track_internal_event(
              'request_import_continuous_sync_stop',
              project: repository.project,
              namespace: repository.project.namespace,
              additional_properties: { label: repository.project.import_type }
            )
          end

          FinishStopWorker.perform_async(repository.id, generation)
          generation
        end

        private

        attr_reader :repository, :requested_at

        def validate_connection!
          return unless repository.disconnected?

          raise ConnectionLostError, 'GitHub must be reconnected before updates can stop'
        end

        def validate_authority!
          return if repository.provider_canonical? || repository.cutover_failed?

          raise InvalidStateError, 'GitHub updates cannot be stopped in the current state'
        end

        def validate_import_not_running!
          return unless repository.project.import_in_progress?

          raise InvalidStateError, 'The import must finish before GitHub updates can stop'
        end

        # Unlike a regular update request this also bumps running and paused domains: the lease guarantees no
        # pass is running, and the final pass must start fresh.
        def request_final_domains!
          states = repository.sync_states_for_update(Import::Sync::RepositoryState.domains.keys)

          states.each_value do |state|
            state.desired_generation += 1
            state.state = :pending
            state.save!
          end
        end

        def log_transition(from, generation)
          ::Gitlab::GithubImport::Logger.info(
            message: 'import sync repository authority changed',
            import_sync_repository_id: repository.id,
            Labkit::Fields::GL_PROJECT_ID => repository.project_id,
            from: from,
            to: 'cutting_over',
            application_generation: generation
          )
        end
      end
    end
  end
end
