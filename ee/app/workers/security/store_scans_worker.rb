# frozen_string_literal: true

module Security
  class StoreScansWorker # rubocop:disable Scalability/IdempotentWorker
    include ApplicationWorker

    data_consistency :always

    worker_resource_boundary :cpu
    sidekiq_options retry: 5
    include SecurityScansQueue

    # Lease contention backs off 1, 2, 4, 8 and 16 minutes, which covers the 30 minute lease TTL.
    # nil keeps the Sidekiq default delay for all other errors.
    sidekiq_retry_in do |count, exception|
      (2**count).minutes.to_i if exception.is_a?(Security::StoreGroupedScansService::LeaseTakenError)
    end

    feature_category :vulnerability_management

    def perform(pipeline_id)
      ::Ci::Pipeline.find_by_id(pipeline_id).try do |pipeline|
        break unless pipeline.project.can_store_security_reports?

        Security::StoreScansService.execute(pipeline)
      end
    end
  end
end
