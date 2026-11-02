# frozen_string_literal: true

module Import
  module Sync
    module Repositories
      # Schedules every data domain of a repository for reconciliation and enqueues one ReconcileWorker.
      class RequestUpdateService
        def initialize(repository, event_at: Time.current)
          @repository = repository
          @event_at = event_at
        end

        # Returns the application generation the ReconcileWorker was enqueued with.
        def execute
          domains = Import::Sync::RepositoryState.domains.keys
          response = ScheduleReconcileService.new(repository, domains: domains, event_at: event_at).execute
          generation = response.payload[:application_generation]
          ReconcileWorker.perform_async(repository.id, generation)
          generation
        end

        private

        attr_reader :repository, :event_at
      end
    end
  end
end
