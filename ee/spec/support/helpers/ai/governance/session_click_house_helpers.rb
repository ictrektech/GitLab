# frozen_string_literal: true

module Ai
  module Governance
    module SessionClickHouseHelpers
      def insert_ai_governance_sessions(*rows)
        expect(clickhouse_fixture(:siphon_ai_governance_sessions, rows)).to be(true)
      end

      def ai_governance_session_row(
        id:, namespace:, user:, session_started_at:, project: nil, source: :gitlab_duo, flow_type: nil,
        agent_type: nil)
        duo = source == :gitlab_duo

        {
          id: id,
          namespace_id: namespace.id,
          project_id: project&.id,
          user_id: user.id,
          workflow_id: duo ? id : nil,
          external_xid: duo ? nil : "xid-#{id}",
          source: ::Ai::Governance::Session.sources.fetch(source),
          flow_type: flow_type,
          agent_type: agent_type,
          created_at: session_started_at,
          updated_at: session_started_at,
          session_started_at: session_started_at,
          traversal_path: namespace.traversal_path(with_organization: true),
          _siphon_replicated_at: session_started_at,
          _siphon_deleted: false
        }
      end

      def ai_governance_session_ids(query)
        ::ClickHouse::Client.select(query.to_sql, :main).pluck('id')
      end
    end
  end
end
