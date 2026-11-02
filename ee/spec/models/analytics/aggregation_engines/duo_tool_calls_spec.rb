# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::AggregationEngines::DuoToolCalls, :click_house, time_travel_to: '2026-01-30',
  type: :aggregation_engine,
  feature_category: :product_analytics do
  let(:engine) { described_class.new(context: engine_context) }
  let(:engine_context) { { scope: described_class.prepare_base_aggregation_scope(project) } }

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_group) { create(:group) }
  let_it_be(:other_project) { create(:project, group: other_group) }

  let(:succeeded) { :tool_succeeded_duo_chat }
  let(:failed) { :tool_failed_duo_chat }

  # Session 1 reads then writes, session 2 only reads, session 3 runs a command,
  # session 4 calls a tool the registry does not know. Timestamps are spread out
  # because the table dedups rows that share its sort key.
  let(:events_data) do
    rows = [
      tool_call(user_id: 1, event: succeeded, session_id: 1, tool_name: 'get_issue'),
      tool_call(user_id: 1, event: succeeded, session_id: 1, tool_name: 'create_issue'),
      tool_call(user_id: 1, event: succeeded, session_id: 2, tool_name: 'list_issues'),
      tool_call(user_id: 1, event: failed, session_id: 2, tool_name: 'get_merge_request'),
      tool_call(user_id: 2, event: failed, session_id: 3, tool_name: 'run_command', flow_type: 'agentic_chat'),
      tool_call(user_id: 2, event: succeeded, session_id: 4, tool_name: 'some_mcp_tool'),
      event_data(user_id: 3, event: :request_duo_chat_response, timestamp: 10.days.ago),
      tool_call(user_id: 4, event: succeeded, session_id: 5, tool_name: 'get_issue', project: other_project)
    ]

    rows.each_with_index.map { |row, index| row.merge(timestamp: 10.days.ago + index.seconds) }
  end

  before do
    clickhouse_fixture(:ai_usage_events, events_data)
  end

  def event_data(user_id:, event:, timestamp:, project: self.project, extras: {})
    namespace = project.project_namespace

    {
      user_id: user_id,
      event: Ai::UsageEvent.events[event],
      timestamp: timestamp,
      namespace_path: namespace.traversal_path(with_organization: false),
      traversal_path: namespace.traversal_path(with_organization: true),
      extras: extras
    }
  end

  def tool_call(user_id:, event:, session_id:, tool_name:, flow_type: 'chat', project: self.project)
    event_data(user_id: user_id, event: event, timestamp: 10.days.ago, project: project,
      extras: { session_id: session_id, tool_name: tool_name, flow_type: flow_type })
  end

  def totals(request)
    engine.execute(request)
  end

  describe '.prepare_base_aggregation_scope' do
    it 'keeps only tool call events inside the scope objects' do
      result = ClickHouse::Client.select(described_class.prepare_base_aggregation_scope(group), :main)

      expect(result.map { |r| r['user_id'] }).to match_array([1, 1, 1, 1, 2, 2])
    end

    it 'raises without scope objects' do
      expect { described_class.prepare_base_aggregation_scope([]) }.to raise_error(ArgumentError)
    end
  end

  describe 'metrics' do
    it 'counts calls, users and sessions and rates the successes' do
      request = {
        metrics: [
          { identifier: :total_count }, { identifier: :users_count }, { identifier: :sessions_count },
          { identifier: :write_sessions_count }, { identifier: :read_only_sessions_count },
          { identifier: :success_rate }
        ]
      }

      expect(engine).to execute_aggregation(request).and_return([
        { total_count: 6, users_count: 2, sessions_count: 4, write_sessions_count: 2,
          read_only_sessions_count: 1, success_rate: be_within(0.001).of(4.0 / 6) }
      ])
    end

    it 'returns a NULL success rate when the filter leaves no calls' do
      request = {
        metrics: [{ identifier: :success_rate }],
        filters: [{ identifier: :tool_name, values: ['no_such_tool'] }]
      }

      expect(engine).to execute_aggregation(request).and_return([{ success_rate: nil }])
    end
  end

  describe 'dimensions' do
    it 'groups by tool name' do
      request = { dimensions: [{ identifier: :tool_name }], metrics: [{ identifier: :total_count }] }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { tool_name: 'get_issue', total_count: 1 },
        { tool_name: 'create_issue', total_count: 1 },
        { tool_name: 'list_issues', total_count: 1 },
        { tool_name: 'get_merge_request', total_count: 1 },
        { tool_name: 'run_command', total_count: 1 },
        { tool_name: 'some_mcp_tool', total_count: 1 }
      ]))
    end

    it 'groups by event' do
      request = { dimensions: [{ identifier: :event }], metrics: [{ identifier: :total_count }] }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { event: 'tool_succeeded_duo_chat', total_count: 4 },
        { event: 'tool_failed_duo_chat', total_count: 2 }
      ]))
    end

    it 'classifies tool access from the tool rules registry, with NULL for unknown tools' do
      request = { dimensions: [{ identifier: :tool_access }], metrics: [{ identifier: :total_count }] }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { tool_access: 'read', total_count: 3 },
        { tool_access: 'write', total_count: 2 },
        { tool_access: nil, total_count: 1 }
      ]))
    end

    it 'gives every access group the session-level read-only verdict' do
      request = {
        dimensions: [{ identifier: :tool_access }],
        metrics: [{ identifier: :sessions_count }, { identifier: :read_only_sessions_count }]
      }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { tool_access: 'read', sessions_count: 2, read_only_sessions_count: 1 },
        { tool_access: 'write', sessions_count: 2, read_only_sessions_count: 0 },
        { tool_access: nil, sessions_count: 1, read_only_sessions_count: 0 }
      ]))
    end

    it 'groups by flow type' do
      request = { dimensions: [{ identifier: :flow_type }], metrics: [{ identifier: :total_count }] }

      expect(engine).to execute_aggregation(request).and_return(match_array([
        { flow_type: 'chat', total_count: 5 },
        { flow_type: 'agentic_chat', total_count: 1 }
      ]))
    end

    it 'resolves group IDs to groups through the association finder' do
      association = described_class.dimensions.find { |dimension| dimension.identifier == :group_id }.association

      expect(association[:finder].call([group.id])).to eq(group.id => group)
    end
  end

  describe 'filters' do
    where(:identifier, :value, :expected_total) do
      [
        [:tool_name, %w[get_issue list_issues], 2],
        [:event, %w[tool_failed_duo_chat], 2],
        [:user_id, %w[gid://gitlab/User/2], 2],
        [:user_id_not, %w[gid://gitlab/User/1], 2],
        [:flow_type_not, %w[agentic_chat], 5],
        [:tool_access, %w[write], 2],
        [:flow_type, %w[agentic_chat], 1]
      ]
    end

    with_them do
      it 'limits the calls' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: identifier, values: value }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: expected_total }])
      end
    end

    it 'excludes an access type and the calls whose access is unknown' do
      request = {
        metrics: [{ identifier: :total_count }],
        filters: [{ identifier: :tool_access_not, values: %w[write] }]
      }

      expect(engine).to execute_aggregation(request).and_return([{ total_count: 3 }])
    end

    it 'excludes tool names' do
      request = {
        metrics: [{ identifier: :total_count }],
        filters: [{ identifier: :tool_name_not, values: %w[get_issue] }]
      }

      expect(engine).to execute_aggregation(request).and_return([{ total_count: 5 }])
    end

    it 'limits the calls to a timestamp range' do
      request = {
        metrics: [{ identifier: :total_count }],
        filters: [{ identifier: :timestamp, values: ((10.days.ago + 2.seconds)..) }]
      }

      expect(engine).to execute_aggregation(request).and_return([{ total_count: 4 }])
    end

    context 'when the scope spans groups' do
      let(:engine_context) { { scope: described_class.prepare_base_aggregation_scope([project, other_project]) } }

      it 'limits the calls to the given groups and their descendants' do
        request = {
          metrics: [{ identifier: :total_count }],
          filters: [{ identifier: :group_id, values: [group.to_global_id.to_s] }]
        }

        expect(engine).to execute_aggregation(request).and_return([{ total_count: 6 }])
      end
    end

    context 'with a call that recorded no tool name or flow type' do
      let(:events_data) do
        super() + [event_data(user_id: 5, event: succeeded, timestamp: 9.days.ago, extras: { session_id: 6 })]
      end

      where(:identifier, :value) do
        [
          [:tool_name_not, %w[get_issue]],
          [:flow_type_not, %w[agentic_chat]]
        ]
      end

      with_them do
        it 'excludes that call as well' do
          request = {
            metrics: [{ identifier: :total_count }],
            filters: [{ identifier: identifier, values: value }]
          }

          expect(engine).to execute_aggregation(request).and_return([{ total_count: 5 }])
        end
      end
    end
  end
end
