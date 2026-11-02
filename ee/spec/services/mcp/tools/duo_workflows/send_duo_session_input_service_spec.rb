# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::SendDuoSessionInputService, feature_category: :mcp_server do
  let(:resume_tool) do
    instance_double(Mcp::Tools::Base::ApiTool, name: :resume_duo_workflow, settings: { resource_name: 'workflow' })
  end

  let(:dispatch) { { tool_name: 'resume_duo_workflow' } }
  let(:tools) { [resume_tool] }
  let(:service) { described_class.new(tools: tools) }

  describe '.tool_name' do
    it 'returns the agreed tool name' do
      expect(described_class.tool_name).to eq('send_duo_session_input')
    end
  end

  describe '#description' do
    it 'tells the model which statuses accept input and how to follow up' do
      expect(service.description).to include('input_required', 'plan_approval_required',
        'tool_call_approval_required', 'get_duo_session')
    end

    it 'does not name tools that do not exist' do
      text = [service.description, service.input_schema.to_json].join

      # add_duo_session is planned (#607619) but not registered yet; add it back here once it is.
      expect(text).not_to include('approve_duo_flow', 'approve_duo_agent_action', 'trigger_duo_flow',
        'add_duo_session')
    end
  end

  describe '#annotations' do
    it 'is a non-destructive write' do
      expect(service.annotations).to eq(
        title: 'Send input to Duo session',
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true
      )
    end
  end

  describe '#input_schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(service.input_schema).to eq({
        type: 'object',
        properties: {
          workflow_id: {
            type: 'integer',
            description: 'ID of the Duo session, as returned by list_duo_sessions or get_duo_session.'
          },
          human_approval: {
            type: 'boolean',
            description: 'true approves the pending plan or tool call. Do not combine it with human_message, or ' \
              'the tool rejects the call instead of resuming the session. false rejects it: send ' \
              'human_message so the agent continues with your feedback. Without one, the agent is ' \
              'told not to proceed and the session continues.'
          },
          human_message: {
            type: 'string',
            description: 'Your feedback for the agent, or your answer when the session asked a question, up to ' \
              '2000 characters. Send it with human_approval=false. With human_approval=true, the tool ' \
              'rejects the call instead of resuming the session.',
            maxLength: 2000
          }
        },
        required: %w[workflow_id human_approval],
        additionalProperties: false
      })
    end
  end

  describe '#execute' do
    let(:request) { instance_double(Rack::Request) }
    let(:arguments) { { workflow_id: 42, human_approval: true } }
    let(:params) { { arguments: arguments } }

    let(:rest_body) do
      { 'id' => 42, 'status' => 'input_required', 'workflow_definition' => 'software_development',
        'workload' => { 'id' => 7, 'message' => nil } }
    end

    let(:rest_response) do
      Mcp::Tools::Base::Response.success([{ type: 'text', text: rest_body.to_json }], rest_body)
    end

    it 'forwards the arguments to the resume route with workflow_id as a string' do
      expect(resume_tool).to receive(:execute).with(
        request: request,
        params: { arguments: { workflow_id: '42', human_approval: true } }
      ).and_return(rest_response)

      service.execute(request: request, params: params)
    end

    it 'returns a poll hint and the session identifiers instead of the raw workflow entity' do
      allow(resume_tool).to receive(:execute).and_return(rest_response)

      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq(
        'workflow_id' => 42,
        'status' => 'input_required',
        'workload_id' => 7,
        'poll_after_seconds' => described_class::POLL_AFTER_SECONDS
      )
      expect(result.dig(:content, 0, :text)).to include('session 42', 'get_duo_session',
        "workflow_id=42", described_class::POLL_AFTER_SECONDS.to_s)
      expect(result[:dispatch]).to eq(dispatch)
    end

    context 'when the caller answers with a human_message' do
      let(:arguments) { { workflow_id: 42, human_approval: false, human_message: 'pick a safer command' } }

      it 'forwards the decision and the message together' do
        expect(resume_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { workflow_id: '42', human_approval: false, human_message: 'pick a safer command' } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end
    end

    context 'when a human_message rides an approval' do
      let(:arguments) { { workflow_id: 42, human_approval: true, human_message: 'looks good, proceed' } }

      it 'refuses instead of queueing a job duo-cli rejects', :aggregate_failures do
        expect(resume_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:reason]).to eq(:bad_request)
        expect(result.dig(:content, 0, :text)).to include(
          'human_message cannot be sent with human_approval=true', 'human_approval=false'
        )
      end
    end

    context 'when the session is not waiting for input' do
      let(:forbidden) do
        Mcp::Tools::Base::Response.error(
          '403 Forbidden', { 'message' => '403 Forbidden' },
          reason: Mcp::Tools::Base::Response::Reason::UNAUTHORIZED
        )
      end

      it 'explains what to do instead of echoing 403 Forbidden', :aggregate_failures do
        allow(resume_tool).to receive(:execute).and_return(forbidden)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('Session 42 is not waiting for input', 'get_duo_session')
        expect(result[:structuredContent]).to eq(error: { 'message' => '403 Forbidden' })
        expect(result[:reason]).to eq(:unauthorized)
      end

      it 'names the same statuses as the description' do
        allow(resume_tool).to receive(:execute).and_return(forbidden)

        result = service.execute(request: request, params: params)

        expect(result.dig(:content, 0, :text)).to include('input_required', 'plan_approval_required',
          'tool_call_approval_required')
      end
    end

    context 'when the route returns a 403 with a reason' do
      let(:forbidden_with_reason) do
        message = '403 Forbidden - Identity verification is required to use GitLab Duo Agent Platform'

        Mcp::Tools::Base::Response.error(message, { 'message' => message })
      end

      it 'passes the reason through unchanged instead of the resumability guidance' do
        allow(resume_tool).to receive(:execute).and_return(forbidden_with_reason)

        expect(service.execute(request: request, params: params)).to eq(forbidden_with_reason.merge(dispatch: dispatch))
      end
    end

    context 'when the route returns another error' do
      let(:not_found) do
        Mcp::Tools::Base::Response.error('404 Workflow Not Found', { 'message' => '404 Not Found' })
      end

      it 'passes the error through unchanged' do
        allow(resume_tool).to receive(:execute).and_return(not_found)

        expect(service.execute(request: request, params: params)).to eq(not_found.merge(dispatch: dispatch))
      end
    end

    context 'when required arguments are missing' do
      let(:arguments) { { workflow_id: 42 } }

      it 'returns a validation error without calling the route' do
        expect(resume_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('Validation error', 'human_approval is missing')
      end
    end

    context 'when the underlying tool is not registered' do
      let(:tools) { [] }

      it 'returns a tool-not-found error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text))
          .to include("send_duo_session_input is not available on this GitLab instance")
      end
    end
  end
end
