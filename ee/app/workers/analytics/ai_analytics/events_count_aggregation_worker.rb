# frozen_string_literal: true

module Analytics
  module AiAnalytics
    # No-op kept for one release so in-flight jobs finish cleanly.
    # Removal tracked in https://gitlab.com/gitlab-org/gitlab/-/issues/628407
    class EventsCountAggregationWorker
      include ApplicationWorker
      include CronjobQueue # rubocop:disable Scalability/CronWorkerContext -- This worker does not perform work scoped to a context

      idempotent!
      deduplicate :until_executed
      data_consistency :sticky
      feature_category :value_stream_management

      def perform; end
    end
  end
end
