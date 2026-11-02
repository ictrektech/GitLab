# frozen_string_literal: true

module Ai
  module Governance
    class ToolCallsByRiskService
      RISKS = %i[read write destroy unclassified].freeze
      TOOL_NAME_LIMIT = ToolCallsService::TOOL_NAME_LIMIT

      def initialize(container, current_user:, timeframe:, agent_class: :all)
        @container = container
        @current_user = current_user
        @timeframe = MetricsTimeframe.new(timeframe)
        @agent_class = agent_class
      end

      def execute
        return ServiceResponse.error(message: 'ClickHouse is not enabled for analytics') unless clickhouse_enabled?

        response = ClickHouseToolCallsService.new(
          @container,
          current_user: @current_user,
          timeframe: @timeframe,
          agent_class: @agent_class,
          sessions_enabled: Feature.enabled?(:ai_governance_sessions_api, @container.root_ancestor),
          limit: TOOL_NAME_LIMIT + 1
        ).execute

        return response unless response.success?

        ServiceResponse.success(payload: by_risk(response.payload[:tool_calls]))
      end

      private

      def by_risk(tool_calls)
        counts = RISKS.index_with(0)

        tool_calls.first(TOOL_NAME_LIMIT).each do |tool_call|
          counts[risk_of(tool_call[:tool_name])] += tool_call[:count]
        end

        {
          total: counts.values.sum,
          slices: RISKS.map { |risk| { risk: risk, count: counts[risk] } },
          approximate: tool_calls.size > TOOL_NAME_LIMIT
        }
      end

      # Classified exactly as the Top tools card badges each row, so the two cannot disagree.
      def risk_of(tool_name)
        names.resolve(tool_name)[:action_type] || :unclassified
      end

      def names
        @names ||= ToolCallNames.new(@container)
      end

      def clickhouse_enabled?
        ::Gitlab::ClickHouse.enabled_for_analytics?(namespace)
      end

      def namespace
        @container.is_a?(Project) ? @container.project_namespace : @container
      end
    end
  end
end
