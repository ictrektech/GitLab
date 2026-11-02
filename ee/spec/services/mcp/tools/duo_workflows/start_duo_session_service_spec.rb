# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::StartDuoSessionService, feature_category: :mcp_server do
  using RSpec::Parameterized::TableSyntax

  let(:create_tool) do
    instance_double(Mcp::Tools::Base::ApiTool, name: :create_duo_workflow, settings: { resource_name: 'project' })
  end

  let(:tools) { [create_tool] }
  let(:service) { described_class.new(tools: tools) }

  describe '.tool_name' do
    it 'returns the agreed tool name' do
      expect(described_class.tool_name).to eq('start_duo_session')
    end
  end

  describe '#description' do
    it 'advertises the URL' do
      expect(service.description).to include('session id and URL')
    end

    it 'points the model at the tools that follow up on the session' do
      expect(service.description).to include('get_duo_session', 'send_duo_session_input')
    end

    it 'warns that this starts a real CI job' do
      expect(service.description).to include('CI job')
    end

    it 'does not name tools that do not exist' do
      text = [service.description, service.input_schema.to_json].join

      expect(text).not_to include('add_duo_session', 'trigger_duo_flow', 'approve_duo_agent_action')
    end
  end

  describe '#annotations' do
    it 'is a destructive write, so a client filtering destructive tools can hold it back' do
      expect(service.annotations).to eq(
        title: 'Start Duo session',
        readOnlyHint: false,
        destructiveHint: true,
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
          url: {
            type: 'string',
            description: 'GitLab URL of the project the flow runs in (for example, ' \
              'https://gitlab.com/group/project). Do not use with project_id.'
          },
          project_id: {
            type: 'string',
            description: 'ID or full path of the project the flow runs in. Do not use with url.'
          },
          goal: {
            type: 'string',
            description: 'What the agent should do, in prose. This is the prompt the flow starts from. Some ' \
              'GitLab flows take a URL instead: for fix_pipeline/v1, the URL of the failed pipeline, and for ' \
              'code_review/v1, the URL of the merge request. The session then runs on the branch of that ' \
              "pipeline or merge request, and fix_pipeline/v1 posts its suggested fix on the pipeline's open " \
              'merge request, or opens a new merge request if there is none.'
          },
          flow: {
            type: 'string',
            description: 'Reference of a GitLab flow to run, for example developer/v1. ' \
              'Do not use with flow_item_id, ai_catalog_item_consumer_id or agent.'
          },
          flow_item_id: {
            type: 'integer',
            description: 'AI Catalog item ID of a custom flow. The latest released version is run. Do not use ' \
              'with flow, ai_catalog_item_consumer_id or agent.'
          },
          ai_catalog_item_consumer_id: {
            type: 'integer',
            description: 'ID of the AI Catalog item consumer that configures which flow to run. Call ' \
              'list_duo_agents_and_flows to find it: catalog flows are configured per project, so ask ' \
              'the user which flow to run if unsure. Do not use with flow, flow_item_id or agent.'
          },
          agent: {
            type: 'string',
            description: 'Reference of a foundational agent to run, for example analytics_agent/v1. GitLab Duo ' \
              'itself cannot be started. Do not use with flow, flow_item_id or ' \
              'ai_catalog_item_consumer_id.'
          }
        },
        required: %w[goal],
        additionalProperties: false
      })
    end
  end

  describe '#execute' do
    let(:request) { instance_double(Rack::Request) }
    let(:arguments) { { project_id: '7', ai_catalog_item_consumer_id: 42, goal: 'Fix the flaky spec' } }
    let(:params) { { arguments: arguments } }

    let(:rest_body) do
      { 'id' => 99, 'status' => 'created', 'workflow_definition' => 'software_development',
        'web_url' => 'https://gitlab.example.com/group/project/-/automate/agent-sessions/99',
        'workload' => { 'id' => 5, 'message' => nil } }
    end

    let(:rest_response) do
      Mcp::Tools::Base::Response.success([{ type: 'text', text: rest_body.to_json }], rest_body)
    end

    context 'when a GitLab flow is named' do
      let(:arguments) { { project_id: '7', flow: 'code_review/v1', goal: 'Review it' } }

      it 'forwards it as the workflow definition' do
        expect(create_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { project_id: '7', goal: 'Review it', workflow_definition: 'code_review/v1',
                                 start_workflow: true, environment: 'ambient' } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end
    end

    context 'when a foundational agent is named' do
      let(:arguments) { { project_id: '7', agent: 'analytics_agent/v1', goal: 'Look into it' } }

      it 'forwards it as the workflow definition' do
        expect(create_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { project_id: '7', goal: 'Look into it', workflow_definition: 'analytics_agent/v1',
                                 start_workflow: true, environment: 'ambient' } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end

      context 'when it is not a foundational agent' do
        let(:arguments) { { project_id: '7', agent: 'developer/v1', goal: 'Do it' } }

        it 'refuses and points at flow, since a GitLab flow is the likely mix-up' do
          expect(create_tool).not_to receive(:execute)

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text))
            .to include("'developer/v1' is not a foundational agent", 'Pass a GitLab flow as flow')
        end
      end

      where(:definition) { %w[chat agentic_chat/v1] }

      with_them do
        let(:arguments) { { project_id: '7', agent: definition, goal: 'Hi' } }

        it 'refuses GitLab Duo itself, whose sessions list_duo_sessions leaves out' do
          expect(create_tool).not_to receive(:execute)

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include('GitLab Duo itself cannot be started as a session')
        end
      end
    end

    context 'when a foundational agent is named as a flow' do
      let(:arguments) { { project_id: '7', flow: 'analytics_agent/v1', goal: 'Look into it' } }

      it 'refuses and names the parameter to use instead' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include("pass agent: 'analytics_agent/v1' instead of flow")
      end
    end

    context 'when no flow is named' do
      let(:arguments) { { project_id: '7', goal: 'Do it' } }

      it 'defaults to the developer flow' do
        expect(create_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { project_id: '7', goal: 'Do it', environment: 'ambient',
                                 workflow_definition: described_class::DEFAULT_FLOW, start_workflow: true } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end
    end

    context 'when a project URL is given instead of an ID' do
      let(:arguments) { { url: 'https://gitlab.com/group/project', goal: 'Do it' } }

      it 'passes the path, which the route accepts in place of an ID' do
        expect(create_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { project_id: 'group/project', goal: 'Do it', environment: 'ambient',
                                 workflow_definition: described_class::DEFAULT_FLOW, start_workflow: true } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end
    end

    context 'when a catalog item ID is given' do
      let(:arguments) { { project_id: '7', flow_item_id: 11, goal: 'Do it' } }
      let(:version) { instance_double(::Ai::Catalog::ItemVersion, id: 77) }
      let(:item) do
        instance_double(::Ai::Catalog::Item,
          foundational_flow?: false, latest_released_version_with_fallback: version)
      end

      before do
        allow(::Ai::Catalog::Item).to receive(:find_by_id).with(11).and_return(item)
      end

      # The route takes a version ID, so the item has to be resolved first.
      it 'resolves it to the latest released version ID' do
        expect(create_tool).to receive(:execute).with(
          request: request,
          params: { arguments: { project_id: '7', goal: 'Do it', ai_catalog_item_version_id: 77,
                                 workflow_definition: ::Ai::DuoWorkflows::Workflow::AI_CATALOG_AGENT_FLOW_TYPE,
                                 start_workflow: true, environment: 'ambient' } }
        ).and_return(rest_response)

        service.execute(request: request, params: params)
      end

      context 'when the item is a GitLab flow' do
        let(:item) do
          instance_double(::Ai::Catalog::Item,
            foundational_flow?: true, foundational_flow_reference: 'developer/v1')
        end

        it 'refuses and names the flow to use instead' do
          expect(create_tool).not_to receive(:execute)

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include("pass flow: 'developer/v1' instead of flow_item_id")
        end
      end

      context 'when the item has no released version' do
        let(:item) do
          instance_double(::Ai::Catalog::Item,
            foundational_flow?: false, latest_released_version_with_fallback: nil)
        end

        it 'refuses without calling the route' do
          expect(create_tool).not_to receive(:execute)

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text)).to include('has no released version')
        end
      end
    end

    context 'when the catalog item does not exist' do
      let(:arguments) { { project_id: '7', flow_item_id: non_existing_record_id, goal: 'Do it' } }

      it 'refuses without calling the route, as not_found', :aggregate_failures do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result.dig(:content, 0, :text))
          .to eq("Tool execution failed: AI Catalog item '#{non_existing_record_id}' not found")
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end
    end

    context 'when the flow is named more than one way' do
      let(:arguments) { { project_id: '7', flow: 'developer/v1', flow_item_id: 11, goal: 'Do it' } }

      it 'refuses without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('at most one of')
      end
    end

    context 'when both a flow and an agent are named' do
      let(:arguments) { { project_id: '7', flow: 'developer/v1', agent: 'analytics_agent/v1', goal: 'Do it' } }

      it 'refuses without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('at most one of')
      end
    end

    context 'when the project is not named at all' do
      let(:arguments) { { goal: 'Do it' } }

      it 'refuses without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('exactly one of')
      end
    end

    context 'when the URL names a group rather than a project' do
      let(:arguments) { { url: 'https://gitlab.com/groups/my-group', goal: 'Do it' } }

      it 'says the URL is the problem rather than letting the route report a missing project' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('does not name a project')
      end
    end

    context 'when the URL names no project' do
      let(:arguments) { { url: 'https://gitlab.com', goal: 'Do it' } }

      it 'says the URL is the problem rather than letting the route report a missing project' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('does not name a project')
      end
    end

    context 'when the project is named both ways' do
      let(:arguments) { { url: 'https://gitlab.com/g/p', project_id: '7', goal: 'Do it' } }

      it 'refuses without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('exactly one of')
      end
    end

    it 'forces start_workflow so the session actually runs' do
      expect(create_tool).to receive(:execute).with(
        request: request,
        params: { arguments: arguments.merge(start_workflow: true, environment: 'ambient') }
      ).and_return(rest_response)

      service.execute(request: request, params: params)
    end

    it 'rejects arguments outside the schema, so source_type cannot be spoofed' do
      expect(create_tool).not_to receive(:execute)

      result = service.execute(
        request: request,
        params: { arguments: arguments.merge(source_type: :slack) }
      )

      expect(result[:isError]).to be(true)
      expect(result.dig(:content, 0, :text)).to include('Validation error')
    end

    it 'returns the canonical session URL alongside the poll hint and identifiers' do
      allow(create_tool).to receive(:execute).and_return(rest_response)

      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]).to eq(
        'workflow_id' => 99,
        'status' => 'created',
        'workload_id' => 5,
        'poll_after_seconds' => described_class::POLL_AFTER_SECONDS,
        'web_url' => rest_body['web_url']
      )
      expect(result.dig(:content, 0, :text)).to include('Session 99 started', 'get_duo_session',
        'workflow_id=99', described_class::POLL_AFTER_SECONDS.to_s, rest_body['web_url'])
      expect(result[:dispatch]).to eq(tool_name: 'create_duo_workflow')
    end

    context 'when the route started the session without a CI workload' do
      let(:rest_body) { super().merge('workflow_definition' => 'analytics_agent/v1', 'workload' => nil) }

      it 'says the session runs without a CI job, with the shorter poll hint', :aggregate_failures do
        allow(create_tool).to receive(:execute).and_return(rest_response)

        result = service.execute(request: request, params: params)

        expect(result[:structuredContent]).to include(
          'workload_id' => nil,
          'poll_after_seconds' => described_class::WORKHORSE_POLL_AFTER_SECONDS
        )
        expect(result.dig(:content, 0, :text)).to include('It runs without a CI job',
          "in #{described_class::WORKHORSE_POLL_AFTER_SECONDS} seconds")
        expect(result.dig(:content, 0, :text)).not_to include('CI job, which')
      end
    end

    it 'leaves authorization to the route it dispatches to' do
      allow(create_tool).to receive(:execute).and_return(rest_response)

      expect(Ability).not_to receive(:allowed?)

      service.execute(request: request, params: params)
    end

    context 'when the route returns an error it already explains' do
      let(:bad_request) do
        Mcp::Tools::Base::Response.error('400 Bad request - goal is missing', { 'message' => '400 Bad request' })
      end

      it 'passes it through unchanged' do
        allow(create_tool).to receive(:execute).and_return(bad_request)

        expect(service.execute(request: request, params: params))
          .to eq(bad_request.merge(dispatch: { tool_name: 'create_duo_workflow' }))
      end
    end

    context 'when the caller may not run the flow' do
      let(:rest_body) { { 'message' => '400 Bad request - ["You have insufficient permissions"]' } }
      let(:refusal) do
        Mcp::Tools::Base::Response.error(
          rest_body['message'], rest_body, reason: Mcp::Tools::Base::Response::Reason::BAD_REQUEST
        )
      end

      it 'names both the role and the flow, and keeps the REST body for context', :aggregate_failures do
        allow(create_tool).to receive(:execute).and_return(refusal)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('Developer role', 'No session was started')
        expect(result[:structuredContent]).to eq(error: rest_body)
        expect(result[:dispatch]).to eq(tool_name: 'create_duo_workflow')
      end

      it 'logs a role refusal as unauthorized, not as the 400 the API answered with' do
        allow(create_tool).to receive(:execute).and_return(refusal)

        result = service.execute(request: request, params: params)

        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end

      it 'does not claim the role is the only thing to fix' do
        allow(create_tool).to receive(:execute).and_return(refusal)

        result = service.execute(request: request, params: params)

        expect(result.dig(:content, 0, :text)).to include('the flow must be available')
      end
    end

    context 'when the flow has no composite identity service account' do
      let(:rest_body) do
        { 'message' => '403 Forbidden - A composite identity service account is required to start this workflow.' }
      end

      let(:refusal) do
        Mcp::Tools::Base::Response.error(
          rest_body['message'], rest_body, reason: Mcp::Tools::Base::Response::Reason::UNAUTHORIZED
        )
      end

      it 'says what to configure instead of repeating the bare 403', :aggregate_failures do
        allow(create_tool).to receive(:execute).and_return(refusal)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text))
          .to include('composite identity service account', 'AI Catalog', 'No session was started')
        expect(result.dig(:content, 0, :text)).not_to include('403 Forbidden')
        expect(result[:reason]).to eq(:unauthorized)
      end

      context 'when a foundational agent was named' do
        let(:arguments) { { project_id: '7', agent: 'analytics_agent/v1', goal: 'Fix the flaky spec' } }

        it 'does not send the caller to the AI Catalog, which has nothing to configure for it', :aggregate_failures do
          allow(create_tool).to receive(:execute).and_return(refusal)

          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result.dig(:content, 0, :text))
            .to include('foundational agents', 'cannot be started', 'No session was started')
          expect(result.dig(:content, 0, :text)).not_to include('AI Catalog')
        end
      end
    end

    context 'when required arguments are missing' do
      let(:arguments) { { project_id: '7' } }

      it 'returns a validation error without calling the route' do
        expect(create_tool).not_to receive(:execute)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include('Validation error')
      end
    end

    context 'when the underlying tool is not registered' do
      let(:tools) { [] }

      it 'returns a tool-not-found error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result.dig(:content, 0, :text)).to include("start_duo_session is not available on this GitLab instance")
      end
    end
  end

  describe '#governed_containers' do
    let_it_be(:project) { create(:project) }
    let_it_be(:publisher_project) { create(:project) }
    let_it_be(:consumer_group) { create(:group) }
    let_it_be(:flow_item) { create(:ai_catalog_flow, :public, project: publisher_project) }
    let_it_be(:consumer) do
      create(:ai_catalog_item_consumer, :parent_item_consumer, item: flow_item, group: consumer_group)
    end

    subject(:resolved) { service.governed_containers(arguments.with_indifferent_access) }

    context 'when the session runs a catalog flow by its item id' do
      let(:arguments) { { project_id: project.id.to_s, flow_item_id: flow_item.id, goal: 'Do it' } }

      it 'governs the session by the project it runs in, not the project that published the flow',
        :aggregate_failures do
        expect(resolved.containers).to eq([project])
        expect(resolved.named).to eq(1)
      end
    end

    context 'when the session runs a flow through an item consumer' do
      let(:arguments) { { project_id: project.id.to_s, ai_catalog_item_consumer_id: consumer.id, goal: 'Do it' } }

      it 'governs the session by the project and the consumer group', :aggregate_failures do
        expect(resolved.containers).to contain_exactly(project, consumer_group)
        expect(resolved.named).to eq(2)
      end
    end

    context 'when the item consumer does not exist' do
      let(:arguments) do
        { project_id: project.id.to_s, ai_catalog_item_consumer_id: non_existing_record_id, goal: 'Do it' }
      end

      it 'still counts the consumer as named, with no container for it', :aggregate_failures do
        expect(resolved.containers).to eq([project])
        expect(resolved.named).to eq(2)
      end
    end
  end
end
