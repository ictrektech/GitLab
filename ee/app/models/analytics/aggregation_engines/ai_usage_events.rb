# frozen_string_literal: true

module Analytics
  module AggregationEngines
    class AiUsageEvents < Gitlab::Database::Aggregation::ClickHouse::Engine
      self.table_name = 'ai_usage_events'

      EVENTS = Gitlab::Tracking::AiTracking.registered_events.freeze

      transient(:feature) do
        when_clauses = Gitlab::Tracking::AiTracking.registered_features.map do |feature|
          event_ids = Gitlab::Tracking::AiTracking.registered_events(feature).values
          "WHEN event IN (#{event_ids.join(', ')}) THEN '#{feature}'"
        end

        sql("CASE #{when_clauses.join(' ')} ELSE NULL END")
      end

      transient(:flow_type) { sql("nullIf(JSONExtractString(extras, 'flow_type'), '')") }

      dimensions do
        column :feature, :string, transient(:feature), description: 'Feature identifier'
        column :flow_type, :string, transient(:flow_type),
          description: 'Duo Agent Platform flow type; NULL for non-DAP events'
        column :event, :string, description: 'Event identifier',
          formatter: ->(value) { Ai::UsageEvent.events.key(value) }
        column :user_id, :integer, description: 'Event owner', association: true
        traversal_path :group_id, :integer, -> { sql('traversal_path') },
          association: {
            finder: ->(ids) { Group.id_in(ids).with_route.index_by(&:id) },
            preloader: Preloaders::GroupPolicyPreloader
          },
          description: 'Group at the requested depth of the hierarchy. ' \
            'NULL for events tracked above that depth. Events tracked in a project at that depth ' \
            'bucket by project namespace ID, which also resolves to NULL.'
        date_bucket :timestamp, :date, -> {
          sql('timestamp')
        }, description: 'Event date'
      end

      metrics do
        count description: 'Total number of events, optionally filtered by event name',
          parameters: {
            event: { type: :string, in: EVENTS.keys, array: true,
                     description: 'Only count the given events.',
                     formatter: ->(values) { EVENTS.values_at(*values) } }
          }
        count :users, :integer, -> { sql('user_id') }, distinct: true, description: 'Number of unique users'
        count :features, :integer, transient(:feature), distinct: true, description: 'Number of unique features'
        retained_count :returning_users, :integer, -> { sql('user_id') }, over: :timestamp,
          description: 'Number of users who also used this feature in the previous period'
        lagged_count :previous_period_users, :integer, -> { sql('user_id') }, over: :timestamp,
          description: 'Number of unique users in the previous period'
      end

      filters do
        exact_match :user_id, :string, description: 'Filter by one or many user Global IDs',
          formatter: gid_formatter
        exact_not_match :user_id, :string,
          description: "Exclude one or many user Global IDs. Maximum is #{MAX_EXCLUSION_VALUES}.",
          formatter: gid_formatter, max_size: MAX_EXCLUSION_VALUES
        descendants :group_id, :string, -> { sql('traversal_path') }, max_size: 100,
          description: 'Filter by one or many group Global IDs, including events from their descendants'
        exact_match :event, :string, description: 'Filter by one or many events',
          formatter: ->(values) { Array.wrap(values).filter_map { |v| Ai::UsageEvent.events[v] } }
        exact_not_match :event, :string,
          description: 'Exclude one or many events. Unrecognized values are ignored, so a list ' \
            "with none recognized excludes nothing. Maximum is #{MAX_EXCLUSION_VALUES}.",
          formatter: ->(values) { Array.wrap(values).filter_map { |v| Ai::UsageEvent.events[v] } },
          max_size: MAX_EXCLUSION_VALUES
        exact_match :feature, :string, transient(:feature), description: 'Filter by one or many features'
        exact_not_match :feature, :string, transient(:feature),
          description: 'Exclude one or many features. Events with no recognized feature are ' \
            "excluded as well. Maximum is #{MAX_EXCLUSION_VALUES}.",
          max_size: MAX_EXCLUSION_VALUES
        exact_match :flow_type, :string, transient(:flow_type),
          description: 'Filter by one or many Duo Agent Platform flow types'
        exact_not_match :flow_type, :string, transient(:flow_type),
          description: 'Exclude one or many Duo Agent Platform flow types. Returns only Duo Agent ' \
            'Platform events, because events from elsewhere have no flow type. ' \
            "Maximum is #{MAX_EXCLUSION_VALUES}.",
          max_size: MAX_EXCLUSION_VALUES
        range :timestamp, :datetime, description: 'Filter by event timestamp'
        metric_range :features_count, :integer, description: 'Filter by the number of unique features'
      end

      def self.prepare_base_aggregation_scope(objects)
        builder = ClickHouse::Client::QueryBuilder.new(table_name)

        conditions = Array.wrap(objects).map do |object|
          namespace = object.is_a?(Project) ? object.project_namespace : object

          builder.func('startsWith', [
            builder[:traversal_path], Arel::Nodes.build_quoted(namespace.traversal_path(with_organization: true).to_s)
          ])
        end

        raise ArgumentError, 'at least one scope object is required' if conditions.empty?

        builder.where(conditions.reduce(:or))
      end
    end
  end
end
