# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Mcp::Handlers::CallTool, feature_category: :mcp_server do
  resolution = Mcp::Tools::Concerns::GovernanceContainerResolver::GovernanceContainerResolutionResult

  let(:manager) { instance_double(Mcp::Tools::Manager) }
  let(:request) { instance_double(Rack::Request) }
  let_it_be(:current_user) { create(:user) }
  let(:tool_lookup) { { name: tool_name, context: nil } }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  subject(:handler) { described_class.new(manager) }

  describe '#invoke' do
    let(:tool_name) { 'test_tool' }
    let(:arguments) { { param: 'value' } }
    let(:params) { { name: tool_name, arguments: arguments } }
    let(:success_result) { { content: [{ type: 'text', text: 'Success' }] } }
    let(:tool_class) { Class.new(Mcp::Tools::Base::BaseService) }
    let(:tool) { tool_class.new(name: tool_name) }
    let(:no_containers) do
      Mcp::Tools::Concerns::GovernanceContainerResolver::GovernanceContainerResolutionResult.none
    end

    before do
      allow(request).to receive(:[]).with(:id).and_return('1')
      allow(manager).to receive(:get_tool).with(**tool_lookup).and_return(tool)
      allow(manager).to receive(:resolve_alias) { |name| name }
      allow(tool).to receive(:execute).and_return(success_result)
      allow(handler).to receive(:track_internal_event)
    end

    context 'when tool is found and version matches' do
      it 'executes the tool successfully and tracks events' do
        result = handler.invoke(request, params, current_user)

        expect(manager).to have_received(:get_tool).with(**tool_lookup)
        expect(tool).to have_received(:execute).with(request: request, params: params)
        expect(result).to eq({ content: [{ type: 'text', text: 'Success' }] })

        expect(handler).to have_received(:track_internal_event).with(
          'start_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, request_id: '1')
        )

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'true')
        )
      end
    end

    context 'when the client identity is known' do
      let(:client_info) { Gitlab::Mcp::ClientInfo.new(name: 'Cursor', version: '1.0.0') }

      subject(:invoke) { handler.invoke(request, params, current_user, client_info: client_info) }

      before do
        allow(handler).to receive(:track_internal_event).and_call_original
      end

      it 'tracks the client name and version as properties on the start and finish events' do
        expect { invoke }
          .to trigger_internal_events('start_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: tool_name, mcp_client_name: 'Cursor', mcp_client_version: '1.0.0'
            }
          )
          .and trigger_internal_events('finish_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: tool_name, has_tool_call_success: 'true',
              mcp_client_name: 'Cursor', mcp_client_version: '1.0.0'
            }
          )
      end

      context 'when the version is unknown' do
        let(:client_info) { Gitlab::Mcp::ClientInfo.new(name: 'node') }

        it 'tracks only the client name' do
          invoke

          expect(handler).to have_received(:track_internal_event)
            .with('start_mcp_tool_call', hash_including(additional_properties: hash_including(mcp_client_name: 'node')))
          expect(handler).not_to have_received(:track_internal_event)
            .with('start_mcp_tool_call', hash_including(additional_properties: hash_including(:mcp_client_version)))
        end
      end
    end

    it 'does not track canonical_tool_name for a canonical call' do
      handler.invoke(request, params, current_user)

      expect(handler).to have_received(:track_internal_event)
        .with('start_mcp_tool_call', hash_including(additional_properties: hash_excluding(:canonical_tool_name)))
      expect(handler).to have_received(:track_internal_event)
        .with('finish_mcp_tool_call', hash_including(additional_properties: hash_excluding(:canonical_tool_name)))
    end

    context 'when the tool is called by an alias' do
      let(:tool_name) { 'legacy_tool' }

      subject(:invoke) { handler.invoke(request, params, current_user) }

      before do
        allow(manager).to receive(:resolve_alias).with('legacy_tool').and_return('test_tool')
        allow(handler).to receive(:track_internal_event).and_call_original
      end

      it 'tracks the name as sent alongside the canonical name on the start and finish events' do
        expect { invoke }
          .to trigger_internal_events('start_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: 'legacy_tool', canonical_tool_name: 'test_tool'
            }
          )
          .and trigger_internal_events('finish_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: 'legacy_tool', canonical_tool_name: 'test_tool',
              has_tool_call_success: 'true'
            }
          )
      end
    end

    context 'when tool is a custom service' do
      let(:custom_tool) { instance_double(Mcp::Tools::Base::CustomService, governed_containers: resolution.none) }

      before do
        allow(manager).to receive(:get_tool).with(**tool_lookup).and_return(custom_tool)
        allow(custom_tool).to receive(:is_a?).with(Mcp::Tools::Base::CustomService).and_return(true)
        allow(custom_tool).to receive(:is_a?).with(Mcp::Tools::Base::GraphqlService).and_return(false)
        allow(custom_tool).to receive(:is_a?).with(Mcp::Tools::Base::AggregatedService).and_return(false)
        allow(custom_tool).to receive(:set_cred)
        allow(custom_tool).to receive_messages(
          governed_containers: no_containers,
          execute: { content: [{ type: 'text', text: 'Success' }] }
        )
      end

      it 'sets credentials before executing and tracks events' do
        result = handler.invoke(request, params, current_user)

        expect(custom_tool).to have_received(:set_cred).with(current_user: current_user, access_token: nil)
        expect(custom_tool).to have_received(:execute).with(request: request, params: params)
        expect(result).to eq({ content: [{ type: 'text', text: 'Success' }] })

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'true')
        )
      end
    end

    context 'when tool is a graphql service' do
      let(:graphql_tool) { instance_double(Mcp::Tools::Base::GraphqlService, governed_containers: resolution.none) }

      before do
        allow(manager).to receive(:get_tool).with(**tool_lookup).and_return(graphql_tool)
        allow(graphql_tool).to receive(:is_a?).with(Mcp::Tools::Base::CustomService).and_return(false)
        allow(graphql_tool).to receive(:is_a?).with(Mcp::Tools::Base::GraphqlService).and_return(true)
        allow(graphql_tool).to receive(:is_a?).with(Mcp::Tools::Base::AggregatedService).and_return(false)
        allow(graphql_tool).to receive(:set_cred)
        allow(graphql_tool).to receive_messages(
          governed_containers: no_containers,
          execute: { content: [{ type: 'text', text: 'Success' }] }
        )
      end

      it 'sets credentials before executing and tracks events' do
        result = handler.invoke(request, params, current_user)

        expect(graphql_tool).to have_received(:set_cred).with(current_user: current_user, access_token: nil)
        expect(graphql_tool).to have_received(:execute).with(request: request, params: params)
        expect(result).to eq({ content: [{ type: 'text', text: 'Success' }] })

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments do not contain project_id or group_id' do
      it 'tracks events without a project or namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'start_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, request_id: '1')
        )

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments include a project_id as an integer id' do
      let(:arguments) { { project_id: project.id.to_s } }

      it 'tracks events with the project (namespace auto-derived by InternalEvents)' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'start_mcp_tool_call',
          user: current_user,
          project: project,
          additional_properties: hash_including(tool_name: tool_name)
        )

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          project: project,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments include a project_id as a full path' do
      let(:arguments) { { project_id: project.full_path } }

      it 'resolves the project from its full path' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          project: project,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments include a group_id as an integer id' do
      let(:arguments) { { group_id: group.id.to_s } }

      it 'tracks events with the group as the namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          namespace: group,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments include a group_id as a full path' do
      let(:arguments) { { group_id: group.full_path } }

      it 'resolves the group from its full path' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          namespace: group,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments use string keys (JSON-originated params)' do
      let(:params) { { name: tool_name, 'arguments' => { 'project_id' => project.id.to_s } } }

      it 'still resolves the project from string-keyed arguments' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          project: project,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when project_id is invalid or unknown' do
      let(:arguments) { { project_id: 'non-existent/project' } }

      it 'falls back to tracking without a project or namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when project_id is an unknown numeric id' do
      let(:arguments) { { project_id: non_existing_record_id.to_s } }

      it 'falls back to tracking without a project or namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when the tool raises an unexpected exception' do
      before do
        allow(tool).to receive(:execute).and_raise(StandardError, 'boom')
      end

      it 'records the generic category rather than the exception class' do
        expect { handler.invoke(request, params, current_user) }.to raise_error(StandardError, 'boom')

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(
            tool_name: tool_name,
            has_tool_call_success: 'false',
            failure_reason: 'error'
          )
        )
      end
    end

    context 'when the tool returns a response-level error' do
      let(:error_result) do
        {
          content: [{ type: 'text', text: 'Validation error: labels is invalid' }],
          structuredContent: {},
          isError: true,
          reason: Mcp::Tools::Base::Response::Reason::BAD_REQUEST
        }
      end

      before do
        allow(tool).to receive(:execute).and_return(error_result)
      end

      it 'tracks the finish event as a failure' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(
            tool_name: tool_name,
            has_tool_call_success: 'false',
            failure_reason: 'bad_request'
          )
        )
      end
    end

    context 'when the tool returns an Orbit query' do
      let(:logger) { instance_double(Gitlab::Mcp::Logger, conditional_info: nil) }
      let(:orbit_query) { Analytics::Orbit::CommandInterceptor::OrbitQuery.new({}, query_response) }

      before do
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
        allow(tool).to receive(:execute).and_return(orbit_query)
      end

      context 'when the query failed' do
        let(:query_response) do
          Analytics::KnowledgeGraph::QueryRunner::McpRenderer.new(1).query_error('compile_error', 'bad query', nil)
        end

        it 'logs the failure and returns the Orbit query unchanged', :aggregate_failures do
          expect(handler.invoke(request, params, current_user)).to be(orbit_query)
          expect(logger).to have_received(:conditional_info)
            .with(current_user, hash_including(tool_status: 'bad_request'))
          expect(handler).to have_received(:track_internal_event).with(
            'finish_mcp_tool_call',
            user: current_user,
            additional_properties: hash_including(has_tool_call_success: 'false', failure_reason: 'bad_request')
          )
        end
      end

      context 'when logging the call raises after the query ran' do
        let(:body) { instance_double(Analytics::KnowledgeGraph::QueryRunner::StreamBody, close: nil) }
        let(:query_response) do
          Analytics::KnowledgeGraph::QueryRunner::Response.new(
            status: 200, content_type: 'application/json', body: body
          )
        end

        before do
          allow(logger).to receive(:conditional_info).and_raise(StandardError, 'boom')
        end

        it 'closes the streamed body', :aggregate_failures do
          expect { handler.invoke(request, params, current_user) }.to raise_error(StandardError, 'boom')
          expect(body).to have_received(:close)
        end
      end

      context 'when logging the call raises and the body cannot be closed' do
        let(:query_response) { Analytics::KnowledgeGraph::QueryRunner::Response.json('{}') }

        before do
          allow(logger).to receive(:conditional_info).and_raise(StandardError, 'boom')
        end

        it 'still re-raises the error' do
          expect { handler.invoke(request, params, current_user) }.to raise_error(StandardError, 'boom')
        end
      end

      context 'when the query succeeded' do
        let(:query_response) { Analytics::KnowledgeGraph::QueryRunner::Response.json('{}') }

        it 'logs ok and returns the Orbit query', :aggregate_failures do
          expect(handler.invoke(request, params, current_user)).to be(orbit_query)
          expect(logger).to have_received(:conditional_info).with(current_user, hash_including(tool_status: 'ok'))
        end
      end
    end

    context 'when logging the call raises for a result that is not an Orbit query' do
      before do
        allow(Gitlab::Mcp::Logger).to receive(:build)
          .and_return(instance_double(Gitlab::Mcp::Logger).tap do |logger|
            allow(logger).to receive(:conditional_info).and_raise(StandardError, 'boom')
          end)
      end

      it 'tracks the failure and re-raises the error' do
        expect { handler.invoke(request, params, current_user) }.to raise_error(StandardError, 'boom')

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(has_tool_call_success: 'false', failure_reason: 'error')
        )
      end
    end

    context 'when an aggregated tool dispatched the call' do
      let(:dispatch) { { tool_name: 'gitlab_search_in_project' } }

      before do
        allow(handler).to receive(:track_internal_event).and_call_original
      end

      it 'tracks the dispatched sub-tool on the finish event only' do
        allow(tool).to receive(:execute).and_return(success_result.merge(dispatch: dispatch))

        expect { handler.invoke(request, params, current_user) }
          .to trigger_internal_events('finish_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: tool_name, has_tool_call_success: 'true',
              dispatched_tool_name: 'gitlab_search_in_project'
            }
          )
          .and trigger_internal_events('start_mcp_tool_call')
          .with(user: current_user, additional_properties: { request_id: '1', tool_name: tool_name })
      end

      it 'tracks the dispatched sub-tool when the sub-tool returned an error' do
        error_result = Mcp::Tools::Base::Response.error('404 Not Found', reason: :not_found).merge(dispatch: dispatch)
        allow(tool).to receive(:execute).and_return(error_result)

        expect { handler.invoke(request, params, current_user) }
          .to trigger_internal_events('finish_mcp_tool_call')
          .with(
            user: current_user,
            additional_properties: {
              request_id: '1', tool_name: tool_name, has_tool_call_success: 'false',
              dispatched_tool_name: 'gitlab_search_in_project',
              failure_reason: 'not_found', error_status: '404 Not Found'
            }
          )
          .and trigger_internal_events('start_mcp_tool_call')
          .with(user: current_user, additional_properties: { request_id: '1', tool_name: tool_name })
      end
    end

    context 'when the tool is not aggregated' do
      it 'does not track dispatch properties on the finish event' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          hash_including(
            additional_properties: hash_excluding(:dispatched_tool_name)
          )
        )
      end
    end

    context 'when group_id is invalid or unknown' do
      let(:arguments) { { group_id: 'non-existent/group' } }

      it 'falls back to tracking without a project or namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when arguments include both a project_id and a group_id' do
      let(:arguments) { { project_id: project.id.to_s, group_id: group.id.to_s } }

      it 'tracks the event with both the project and the group namespace' do
        handler.invoke(request, params, current_user)

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          project: project,
          namespace: group,
          additional_properties: hash_including(has_tool_call_success: 'true')
        )
      end
    end

    context 'when the scope is resolved for both the start and finish events' do
      let(:arguments) { { project_id: project.id.to_s } }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
      end

      it 'resolves the scope once and reuses it for both events and the log line' do
        expect(tool).to receive(:governed_containers).once.and_call_original

        handler.invoke(request, params, current_user)
      end
    end

    context 'when tool is not found' do
      let(:arguments) { { project_id: project.id.to_s } }

      before do
        allow(manager).to receive(:get_tool).with(**tool_lookup)
          .and_raise(Mcp::Tools::Manager::ToolNotFoundError.new(tool_name))
      end

      it 'raises ArgumentError and tracks both start and finish events without looking up a container' do
        recorder = ActiveRecord::QueryRecorder.new do
          expect { handler.invoke(request, params, current_user) }
            .to raise_error(ArgumentError, "Tool '#{tool_name}' not found.")
        end

        # The audit fallback to the user's default namespace reads projects only in a subquery.
        expect(recorder.log.grep(/\ASELECT "projects"\./)).to be_empty

        expect(handler).to have_received(:track_internal_event).with(
          'start_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, request_id: '1')
        )

        expect(handler).to have_received(:track_internal_event).with(
          'finish_mcp_tool_call',
          user: current_user,
          additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'false')
        )
      end

      context 'when mcp_container_lookup_cap is disabled' do
        before do
          stub_feature_flags(mcp_container_lookup_cap: false)
        end

        it 'tracks both start and finish events with the resolved project' do
          expect { handler.invoke(request, params, current_user) }.to raise_error(ArgumentError)

          expect(handler).to have_received(:track_internal_event).with(
            'start_mcp_tool_call',
            user: current_user,
            project: project,
            additional_properties: hash_including(tool_name: tool_name, request_id: '1')
          )

          expect(handler).to have_received(:track_internal_event).with(
            'finish_mcp_tool_call',
            user: current_user,
            project: project,
            additional_properties: hash_including(tool_name: tool_name, has_tool_call_success: 'false')
          )
        end
      end
    end

    context 'when logging the tool call' do
      let(:logger) { instance_double(Gitlab::Mcp::Logger) }

      before do
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:conditional_info)
      end

      context 'when arguments include a project_id' do
        let(:arguments) { { project_id: project.id.to_s } }

        it 'gates expanded logging on the root ancestor of the project namespace' do
          handler.invoke(request, params, current_user)

          expect(logger).to have_received(:conditional_info).with(
            current_user, hash_including(namespace: project.root_ancestor)
          )
        end
      end

      context 'when arguments include a group_id' do
        let(:arguments) { { group_id: group.id.to_s } }

        it 'gates expanded logging on the root ancestor of the group' do
          handler.invoke(request, params, current_user)

          expect(logger).to have_received(:conditional_info).with(
            current_user, hash_including(namespace: group.root_ancestor)
          )
        end
      end

      context 'when arguments contain no project_id or group_id' do
        it 'passes a nil namespace' do
          handler.invoke(request, params, current_user)

          expect(logger).to have_received(:conditional_info).with(
            current_user, hash_including(namespace: nil)
          )
        end
      end
    end

    describe 'audit events' do
      let(:capture_service) { instance_double(::Mcp::Audit::CaptureEventService, job_attributes: {}) }
      let(:session) { create(:ai_governance_session, :mcp, user: current_user, namespace: group) }

      before do
        allow(::Mcp::Audit::CaptureEventService).to receive(:new).and_return(capture_service)
        allow(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to receive(:perform_async)
        allow(::Mcp::Audit::ResolveSessionService).to receive(:new)
          .and_return(instance_double(::Mcp::Audit::ResolveSessionService, execute: session))
      end

      it 'captures a tool_invoked event once the call has succeeded' do
        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(kind: :tool_invoked, session: session, tool_name: tool_name))
      end

      it 'does not capture a failure event for a successful call' do
        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
          .with(hash_including(kind: :tool_failed))
      end

      it 'captures the measured duration' do
        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(duration_s: kind_of(Numeric)))
      end

      # Aggregated tools reassign params[:arguments] to the shape they dispatch, so
      # the record would otherwise hold that instead of what the agent asked for.
      it 'captures the arguments as the agent sent them' do
        allow(tool).to receive(:execute) do |params:, **|
          params[:arguments] = { id: 'rewritten' }
          success_result
        end

        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(arguments: { 'param' => 'value' }))
      end

      # These records stream to external destinations, so secrets must never reach them.
      # The exact match also fails if the filter widens and drops the resource id.
      context 'when the arguments carry a secret' do
        let(:arguments) { { project_id: 'g/p', private_token: 'glpat-secret' } }

        it 'redacts it and keeps the rest' do
          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
            .with(hash_including(arguments: { 'project_id' => 'g/p', 'private_token' => '[FILTERED]' }))
        end
      end

      it 'captures the sub-tool an aggregated tool routed to' do
        allow(tool).to receive(:execute).and_return(
          success_result.merge(described_class::DISPATCH_KEY => { tool_name: 'update_merge_request' })
        )

        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(dispatched_tool_name: 'update_merge_request'))
      end

      # Nothing is recorded before the tool runs, so every event carries a
      # known outcome rather than one nothing later resolves.
      it 'captures exactly one event for a successful call' do
        handler.invoke(request, params, current_user)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(kind: :tool_invoked)).once
      end

      context 'when the tool reports a response-level error' do
        before do
          allow(tool).to receive(:execute).and_return(
            { content: [{ type: 'text', text: 'Validation error' }], structuredContent: {}, isError: true }
          )
        end

        # Tool usage stats count ai_tool_invoked, so a failed call must still emit it.
        it 'captures the invocation and the failure' do
          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
            .with(hash_including(kind: :tool_invoked, error: kind_of(described_class::ToolResponseError))).once
          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
            .with(hash_including(kind: :tool_failed)).once
        end

        it 'queues both events in one job' do
          handler.invoke(request, params, current_user)

          expect(::Ai::DuoWorkflows::ProcessAuditEventsWorker).to have_received(:perform_async)
            .with([{}, {}]).once
        end
      end

      # Duo Agent Platform hands ai_workflows tokens to the external agents it runs in CI
      # as well as to its own executor, and the scope cannot tell them apart.
      context 'when the caller holds a Duo Agent Platform token' do
        before do
          ::Current.token_info = { token_scopes: [::Gitlab::Auth::AI_WORKFLOW, ::Gitlab::Auth::MCP_SCOPE] }
        end

        after do
          ::Current.token_info = nil
        end

        it 'captures the tool call' do
          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
            .with(hash_including(kind: :tool_invoked))
        end
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(mcp_session_audit_events: false)
        end

        it 'captures nothing' do
          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
        end

        # The flag de-risks rollout, so with it off a call must not pay for the session scoping.
        it 'skips the membership and default namespace lookups' do
          expect(handler).not_to receive(:audit_session_container)

          handler.invoke(request, params, current_user)
        end
      end

      # A group rollout must cover every member's calls into the group, and nothing outside it.
      context 'when the feature flag is enabled for one group only' do
        let_it_be(:other_group) { create(:group) }

        before_all do
          group.add_developer(current_user)
          other_group.add_developer(current_user)
        end

        before do
          stub_feature_flags(mcp_session_audit_events: group)
        end

        it 'captures a call into a project of that group' do
          allow(handler).to receive(:resolve_tracking_scope).and_return({ project: project })

          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
        end

        it 'captures nothing for a call into another group' do
          allow(handler).to receive(:resolve_tracking_scope).and_return({ namespace: other_group })

          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
        end

        it 'captures nothing for a call that falls back to the user namespace' do
          allow(handler).to receive(:resolve_tracking_scope).and_return({})

          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
        end

        it 'captures nothing for a call into that group that is audited in the user namespace' do
          allow(handler).to receive_messages(
            resolve_tracking_scope: { project: project }, audit_session_container: current_user.namespace
          )

          handler.invoke(request, params, current_user)

          expect(::Mcp::Audit::CaptureEventService).not_to have_received(:new)
        end
      end

      # An unknown tool carries no declaration of its own, so containers resolve through the
      # default argument names and an empty argument list falls back to the user's namespace.
      context 'when the tool is not found' do
        let(:arguments) { {} }

        before do
          allow(manager).to receive(:get_tool).with(**tool_lookup)
            .and_raise(Mcp::Tools::Manager::ToolNotFoundError.new(tool_name))
        end

        it 'captures a tool_failed event' do
          expect { handler.invoke(request, params, current_user) }.to raise_error(ArgumentError)

          expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
            .with(hash_including(kind: :tool_failed, tool_name: tool_name))
        end

        it 'scopes the session to the user namespace' do
          expect { handler.invoke(request, params, current_user) }.to raise_error(ArgumentError)

          expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
            .with(hash_including(container: current_user.namespace))
        end
      end

      # Auditing must never break a tool call.
      it 'swallows and reports an auditing failure against the tool' do
        allow(capture_service).to receive(:job_attributes).and_raise(StandardError, 'boom')
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), mcp_tool: tool_name)

        expect { handler.invoke(request, params, current_user) }.not_to raise_error
      end

      # The container decides which customer's SIEM stream receives the session's
      # events, so unlike telemetry attribution it is permission checked.
      describe 'session container authorization' do
        context 'when the user cannot read the resolved project' do
          let_it_be(:private_project) { create(:project, :private) }

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ project: private_project })
          end

          it 'falls back to the user namespace' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: current_user.namespace))
          end
        end

        # read_project passes for any signed-in user on a public project, so readability alone
        # would put a non-member's identity and arguments into the owner's audit stream.
        context 'when the user can read the resolved project but is not a member' do
          let_it_be(:public_project) { create(:project, :public) }

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ project: public_project })
          end

          it 'falls back to the user namespace' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: current_user.namespace))
          end
        end

        context 'when the user can read the resolved group but is not a member' do
          let_it_be(:public_group) { create(:group, :public) }

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ namespace: public_group })
          end

          it 'falls back to the user namespace' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: current_user.namespace))
          end
        end

        context 'when an instance admin is not a member of the resolved project' do
          let_it_be(:admin) { create(:admin) }
          let_it_be(:public_project) { create(:project, :public) }

          before do
            allow(admin).to receive(:can_admin_all_resources?).and_return(true)
            allow(handler).to receive(:resolve_tracking_scope).and_return({ project: public_project })
          end

          it 'keeps the session scoped to the project' do
            handler.invoke(request, params, admin)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: public_project))
          end
        end

        # An organization owner administers every project in the organization, so the call
        # belongs in that project's stream even without a membership row.
        context 'when an organization owner is not a member of the resolved project' do
          let_it_be(:private_project) { create(:project, :private) }
          let_it_be(:organization_owner) do
            create(:organization_owner, organization: private_project.organization).user
          end

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ project: private_project })
          end

          it 'keeps the session scoped to the project' do
            handler.invoke(request, params, organization_owner)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: private_project))
          end
        end

        context 'when the user can read the resolved project' do
          before_all do
            project.add_developer(current_user)
          end

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ project: project })
          end

          it 'scopes the session to the project' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: project))
          end
        end

        context 'when the user can read the resolved group' do
          before_all do
            group.add_developer(current_user)
          end

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({ namespace: group })
          end

          it 'scopes the session to the group' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: group))
          end
        end

        context 'when the tool names nothing and the user has a Duo default namespace' do
          let_it_be(:default_namespace) { create(:group) }

          before do
            allow(handler).to receive(:resolve_tracking_scope).and_return({})
            allow(current_user.user_preference).to receive(:duo_default_namespace_with_fallback)
              .and_return(default_namespace)
          end

          it 'prefers it over the personal namespace' do
            handler.invoke(request, params, current_user)

            expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
              .with(hash_including(container: default_namespace))
          end
        end
      end
    end
  end

  describe 'namespace attribution of the tool-call events' do
    let_it_be(:subgroup) { create(:group, :private, parent: group) }
    let_it_be(:private_project) { create(:project, :private, group: subgroup) }

    let(:tool_name) { 'test_tool' }
    let(:params) { { name: tool_name, arguments: arguments } }
    let(:success_result) { { content: [{ type: 'text', text: 'Success' }] } }
    let(:tool_class) { Class.new(Mcp::Tools::Base::BaseService) }
    let(:tool) { tool_class.new(name: tool_name) }
    let(:start_properties) { { request_id: '1', tool_name: tool_name } }
    let(:finish_properties) { start_properties.merge(has_tool_call_success: 'true') }

    subject(:invoke) { handler.invoke(request, params, current_user) }

    before do
      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
      allow(request).to receive(:[]).with(:id).and_return('1')
      allow(manager).to receive(:get_tool).with(**tool_lookup).and_return(tool)
      allow(manager).to receive(:resolve_alias) { |name| name }
      allow(tool).to receive(:execute).and_return(success_result)
    end

    shared_examples 'attributes both events' do
      it 'tracks the start and finish events with the resolved scope' do
        expect { invoke }
          .to trigger_internal_events('start_mcp_tool_call')
          .with(user: current_user, **expected_scope, additional_properties: start_properties)
          .and trigger_internal_events('finish_mcp_tool_call')
          .with(user: current_user, **expected_scope, additional_properties: finish_properties)
      end
    end

    context 'with a project_id argument' do
      let(:arguments) { { project_id: private_project.id.to_s } }
      let(:expected_scope) { { project: private_project } }

      # The user is not a member of the private project: telemetry must not check permissions.
      it_behaves_like 'attributes both events'
    end

    context 'with a URL-encoded project_id path' do
      let(:arguments) { { project_id: ERB::Util.url_encode(private_project.full_path) } }
      let(:expected_scope) { { project: private_project } }

      it_behaves_like 'attributes both events'
    end

    context 'with a group_id argument' do
      let(:arguments) { { group_id: subgroup.full_path } }
      let(:expected_scope) { { namespace: subgroup } }

      it_behaves_like 'attributes both events'
    end

    context 'with a url argument naming a project resource' do
      let(:arguments) { { url: "#{Gitlab.config.gitlab.url}/#{private_project.full_path}/-/merge_requests/1" } }
      let(:expected_scope) { { project: private_project } }

      it_behaves_like 'attributes both events'
    end

    context 'with a url argument naming a group' do
      let(:arguments) { { url: "#{Gitlab.config.gitlab.url}/groups/#{subgroup.full_path}/-/work_items/1" } }
      let(:expected_scope) { { namespace: subgroup } }

      it_behaves_like 'attributes both events'
    end

    context 'with a tool that declares a full_path style argument' do
      let(:arguments) { { full_path: subgroup.full_path } }
      let(:expected_scope) { { namespace: subgroup } }

      before do
        tool_class.container_arguments(project_or_group: :full_path)
      end

      it_behaves_like 'attributes both events'
    end

    context 'with a tool that declares a project_full_path argument' do
      let(:arguments) { { project_full_path: private_project.full_path } }
      let(:expected_scope) { { project: private_project } }

      before do
        tool_class.container_arguments(project: :project_full_path)
      end

      it_behaves_like 'attributes both events'
    end

    context 'with a route-backed API tool called with id' do
      let(:tool_name) { 'fork_repository' }
      let(:tool) { Mcp::Tools::Manager.new.list_tools['fork_repository'] }
      let(:arguments) { { id: private_project.id.to_s } }
      let(:expected_scope) { { project: private_project } }

      it_behaves_like 'attributes both events'
    end

    context 'with an aggregated tool that rewrites its arguments' do
      let(:tool_name) { 'semantic_search' }
      let(:underlying_tool) do
        instance_double(Mcp::Tools::Base::ApiTool, name: 'semantic_code_search', settings: { resource_name: 'project' },
          execute: success_result)
      end

      let(:tool) { Mcp::Tools::SemanticSearch::SemanticSearchService.new(tools: [underlying_tool]) }
      let(:arguments) { { scope: 'code', q: 'auth', project_id: private_project.full_path } }
      let(:expected_scope) { { project: private_project } }
      let(:finish_properties) do
        super().merge(dispatched_tool_name: 'semantic_code_search')
      end

      before do
        allow(tool).to receive(:execute).and_call_original
      end

      it_behaves_like 'attributes both events'

      it 'forwards the rewritten arguments, which no longer carry project_id' do
        invoke

        expect(underlying_tool).to have_received(:execute)
          .with(request: request, params: hash_including(arguments: { q: 'auth', id: private_project.full_path }))
      end
    end

    context 'with a tool marked ungovernable!' do
      let(:tool_class) { Class.new(Mcp::Tools::Base::BaseService) { ungovernable! } }
      let(:arguments) { { project_id: private_project.id.to_s } }
      let(:expected_scope) { {} }

      it_behaves_like 'attributes both events'
    end

    context 'when resolving the scope raises' do
      let(:arguments) { { project_id: private_project.id.to_s } }
      let(:expected_scope) { {} }

      before do
        allow(tool).to receive(:governed_containers).and_raise(ActiveRecord::StatementInvalid)
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it_behaves_like 'attributes both events'

      it 'still returns the tool response and reports the error' do
        expect(invoke).to eq(success_result)
        expect(Gitlab::ErrorTracking).to have_received(:track_exception)
          .with(an_instance_of(ActiveRecord::StatementInvalid), mcp_tool: tool_name).once
      end
    end

    context 'when a container argument names too many containers' do
      let(:arguments) { { project_id: Array.new(101, &:to_s) } }
      let(:expected_scope) { {} }

      it_behaves_like 'attributes both events'
    end

    context 'when logging the tool call' do
      let(:arguments) { { project_id: private_project.id.to_s } }
      let(:logger) { instance_double(Gitlab::Mcp::Logger, conditional_info: nil) }

      before do
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
      end

      it 'logs the root namespace id as an always-indexed field and gates expanded logging on it' do
        invoke

        expect(logger).to have_received(:conditional_info).with(
          current_user,
          hash_including(
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => group.id,
            namespace: group,
            expanded: { arguments: arguments.stringify_keys }
          )
        )
      end
    end
  end

  describe 'tool rule enforcement' do
    let(:tool_name) { 'get_mcp_server_version' }
    let(:params) { { name: tool_name, arguments: { group_id: group.id.to_s } } }
    let(:tool) { instance_double(Mcp::Tools::Base::BaseService) }

    before_all do
      group.add_developer(current_user)
    end

    before do
      allow(request).to receive(:[]).with(:id).and_return('1')
      allow(manager).to receive(:get_tool).with(**tool_lookup).and_return(tool)
      allow(manager).to receive(:resolve_alias) { |name| name }
      allow(tool).to receive(:is_a?).with(Mcp::Tools::Base::CustomService).and_return(false)
      allow(tool).to receive(:is_a?).with(Mcp::Tools::Base::GraphqlService).and_return(false)
      allow(tool).to receive(:is_a?).with(Mcp::Tools::Base::AggregatedService).and_return(false)

      allow(tool).to receive_messages(execute: { content: [{ type: 'text', text: 'Success' }] },
        governed_containers: resolution.new([group], named: 1))

      stub_feature_flags(duo_mcp_server_governance_rule_enforcement: group)
    end

    it 'resolves containers once for both tracking and governance' do
      handler.invoke(request, params, current_user)

      expect(tool).to have_received(:governed_containers).once
    end

    context 'when the tool resolves to deny' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
      end

      it 'raises before the tool executes' do
        expect { handler.invoke(request, params, current_user) }
          .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)

        expect(tool).not_to have_received(:execute)
      end

      it 'carries the tool name so the endpoint can report it' do
        expect { handler.invoke(request, params, current_user) }
          .to raise_error(an_object_having_attributes(tool_name: tool_name))
      end

      it 'tracks the refusal as a failed finish' do
        expect do
          handler.invoke(request, params, current_user)
        rescue API::Mcp::Handlers::CallTool::ToolDeniedError
          nil
        end.to trigger_internal_events('finish_mcp_tool_call').with(
          user: current_user,
          namespace: group,
          additional_properties: {
            request_id: '1',
            tool_name: tool_name,
            has_tool_call_success: 'false',
            failure_reason: 'unauthorized',
            error_status: "Tool '#{tool_name}' is denied by tool rules"
          }
        )
      end

      # The denial is the record a compliance reader cares about most, and it is
      # audited from the governance rescue rather than the execution path.
      it 'audits the refusal against the governed group' do
        allow(::Mcp::Audit::CaptureEventService).to receive(:new)
          .and_return(instance_double(::Mcp::Audit::CaptureEventService, execute: nil, job_attributes: {}))
        allow(::Mcp::Audit::ResolveSessionService).to receive(:new).and_call_original

        expect { handler.invoke(request, params, current_user) }
          .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)

        expect(::Mcp::Audit::ResolveSessionService).to have_received(:new)
          .with(hash_including(container: group))
        expect(::Mcp::Audit::CaptureEventService).to have_received(:new).with(hash_including(
          kind: :tool_failed,
          error: kind_of(API::Mcp::Handlers::CallTool::ToolDeniedError),
          failure_reason: 'unauthorized'
        ))
      end

      # A SIEM query for invoked tools must include the calls a policy stopped.
      it 'audits the refusal as an invocation too' do
        allow(::Mcp::Audit::CaptureEventService).to receive(:new)
          .and_return(instance_double(::Mcp::Audit::CaptureEventService, execute: nil, job_attributes: {}))

        expect { handler.invoke(request, params, current_user) }
          .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)

        expect(::Mcp::Audit::CaptureEventService).to have_received(:new)
          .with(hash_including(kind: :tool_invoked, failure_reason: 'unauthorized'))
      end

      it 'logs the refusal' do
        logger = instance_double(Gitlab::Mcp::Logger)
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:conditional_info)

        expect { handler.invoke(request, params, current_user) }
          .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)

        expect(logger).to have_received(:conditional_info).with(
          current_user,
          hash_including(
            event_name: 'tools_call',
            tool_name: tool_name,
            tool_status: 'unauthorized',
            namespace: group,
            ::Labkit::Fields::ERROR_TYPE => 'API::Mcp::Handlers::CallTool::ToolDeniedError'
          )
        )
      end

      context 'when the flag is disabled' do
        before do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
        end

        it 'executes the tool exactly as it does today' do
          expect(handler.invoke(request, params, current_user))
            .to eq({ content: [{ type: 'text', text: 'Success' }] })
        end
      end
    end

    context 'when an argument names too many containers' do
      before do
        allow(tool).to receive(:governed_containers).and_raise(
          Mcp::Tools::Concerns::GovernanceContainerResolver::TooManyContainersError,
          'project_id cannot name more than 100 projects or groups'
        )
      end

      it 'logs the refusal as a bad request' do
        logger = instance_double(Gitlab::Mcp::Logger)
        allow(Gitlab::Mcp::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:conditional_info)

        expect { handler.invoke(request, params, current_user) }.to raise_error(ArgumentError)

        expect(logger).to have_received(:conditional_info).with(
          current_user, hash_including(tool_name: tool_name, tool_status: 'bad_request')
        )
      end
    end

    context 'when both flags are off for every actor' do
      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
      end

      it 'resolves no container for governance and reads no rule' do
        expect(tool).to receive(:governed_containers).once.and_return(resolution.new([group], named: 1))
        expect(::Ai::ToolRules::McpGovernance).not_to receive(:new)

        handler.invoke(request, params, current_user)
      end
    end

    context 'when a denied tool is invoked under an alias' do
      let(:tool_name) { 'get_job_log' }
      let(:canonical_name) { 'get_job' }

      before do
        allow(manager).to receive(:resolve_alias).with(tool_name).and_return(canonical_name)
        create(:ai_tool_rule, namespace: group, tool_name: canonical_name, local_access: :deny)
      end

      it 'refuses the call' do
        expect { handler.invoke(request, params, current_user) }
          .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)

        expect(tool).not_to have_received(:execute)
      end
    end

    context 'when the tool resolves to ask' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :ask)
      end

      it 'executes the tool, because only deny blocks at call time' do
        expect(handler.invoke(request, params, current_user))
          .to eq({ content: [{ type: 'text', text: 'Success' }] })
      end
    end

    context 'when the tool resolves to allow' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :allow)
      end

      it 'executes the tool' do
        expect(handler.invoke(request, params, current_user))
          .to eq({ content: [{ type: 'text', text: 'Success' }] })
      end
    end

    context 'when the tool resolves no namespace' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
        allow(tool).to receive_messages(governed_containers: resolution.none)
      end

      it 'leaves the call ungoverned rather than breaking it' do
        expect(handler.invoke(request, params, current_user))
          .to eq({ content: [{ type: 'text', text: 'Success' }] })
      end

      it 'returns a response identical to the one with governance off' do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
        ungoverned = described_class.new(manager).invoke(request, params, current_user)

        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: group)

        expect(described_class.new(manager).invoke(request, params, current_user)).to eq(ungoverned)
      end
    end

    context 'when an identifier resolves to no container' do
      before do
        create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)
        allow(tool).to receive_messages(governed_containers: resolution.new([], named: 1))
      end

      it 'lets the tool answer for itself' do
        expect(handler.invoke(request, params, current_user))
          .to eq({ content: [{ type: 'text', text: 'Success' }] })
      end
    end

    context 'when the caller cannot read the container' do
      let_it_be(:other_group) { create(:group, :private) }
      let_it_be(:other_project) { create(:project, :private) }

      before do
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: true)
      end

      context 'with a group' do
        before do
          create(:ai_tool_rule, namespace: other_group, tool_name: tool_name, local_access: :deny)
          allow(tool).to receive_messages(
            governed_containers: resolution.new([other_group], named: 1))
        end

        it 'skips governance and lets the tool answer, without revealing the deny rule' do
          expect(handler.invoke(request, params, current_user))
            .to eq({ content: [{ type: 'text', text: 'Success' }] })
        end

        context 'when the group is public' do
          let_it_be(:public_group) { create(:group, :public) }

          before do
            create(:ai_tool_rule, namespace: public_group, tool_name: tool_name, local_access: :deny)
            allow(tool).to receive_messages(
              governed_containers: resolution.new([public_group], named: 1))
          end

          it 'reaches governance, because the rule reveals nothing hidden' do
            expect { handler.invoke(request, params, current_user) }
              .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)
          end
        end
      end

      context 'with a project' do
        before do
          create(:ai_tool_rule, namespace: other_project.root_ancestor, tool_name: tool_name, local_access: :deny)
          allow(tool).to receive_messages(
            governed_containers: resolution.new([other_project], named: 1))
        end

        it 'skips governance and lets the tool answer' do
          expect(handler.invoke(request, params, current_user))
            .to eq({ content: [{ type: 'text', text: 'Success' }] })
        end

        context 'when the caller is a member' do
          before_all do
            other_project.add_guest(current_user)
          end

          it 'reaches governance' do
            expect { handler.invoke(request, params, current_user) }
              .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)
          end
        end
      end

      context 'when only one of several containers is unreadable' do
        before do
          allow(tool).to receive_messages(
            governed_containers: resolution.new([group, other_group], named: 2))
        end

        it 'still governs the readable one' do
          create(:ai_tool_rule, namespace: group, tool_name: tool_name, local_access: :deny)

          expect { handler.invoke(request, params, current_user) }
            .to raise_error(API::Mcp::Handlers::CallTool::ToolDeniedError)
        end

        it 'ignores a deny on the unreadable one' do
          create(:ai_tool_rule, namespace: other_group, tool_name: tool_name, local_access: :deny)

          expect(handler.invoke(request, params, current_user))
            .to eq({ content: [{ type: 'text', text: 'Success' }] })
        end
      end

      context 'when the flag is disabled for the container' do
        before do
          stub_feature_flags(duo_mcp_server_governance_rule_enforcement: false)
          allow(tool).to receive_messages(
            governed_containers: resolution.new([other_group], named: 1))
        end

        it 'executes the tool exactly as it does today' do
          expect(handler.invoke(request, params, current_user))
            .to eq({ content: [{ type: 'text', text: 'Success' }] })
        end

        it 'does not check whether the caller can read the container' do
          expect(Ability).not_to receive(:allowed?).with(current_user, :read_group, other_group)

          handler.invoke(request, params, current_user)
        end
      end
    end
  end
end
