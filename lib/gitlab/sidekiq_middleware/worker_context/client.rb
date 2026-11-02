# frozen_string_literal: true

module Gitlab
  module SidekiqMiddleware
    module WorkerContext
      class Client
        include Gitlab::SidekiqMiddleware::WorkerContext

        def call(worker_class_or_name, job, _queue, _redis_pool, &block)
          worker_class = find_worker(worker_class_or_name.to_s.safe_constantize, job)

          # This is not a worker we know about, perhaps from a gem
          return yield unless worker_class
          return yield unless worker_class.respond_to?(:context_for_arguments)

          context_for_args = worker_class.context_for_arguments(job['args'])

          wrap_in_optional_context(context_for_args) do
            # This should be inside the context for the arguments so
            # that we don't override the feature category on the worker
            # with the one from the caller.

            root_caller_id = Gitlab::ApplicationContext.current_context_attribute(:root_caller_id) ||
              Gitlab::ApplicationContext.current_context_attribute(:caller_id)

            context = {
              root_caller_id: root_caller_id
            }

            if Feature.enabled?(:log_correlation_duration, :instance, type: :gitlab_com_derisk)
              context[:root_started_at] = root_started_at
            end

            # We do not want to set anything explicitly in the context
            # when the feature category is 'not_owned'.
            unless worker_class.feature_category_not_owned?
              context[:feature_category] = worker_class.get_feature_category.to_s
            end

            Gitlab::ApplicationContext.with_context(**context, &block)
          end
        end

        private

        # A job enqueued by another job inherits the start of its chain through the context.
        # A job enqueued by a request starts the chain at the request start, so the value is
        # not part of the request context and stays out of request logs. A job enqueued
        # elsewhere, like a cron job, starts the chain now.
        def root_started_at
          Gitlab::ApplicationContext.current_context_attribute(:root_started_at) ||
            Gitlab::RequestContext.instance.request_start_time ||
            Time.now.utc.to_f
        end
      end
    end
  end
end
