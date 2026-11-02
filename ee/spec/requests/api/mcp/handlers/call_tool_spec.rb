# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat -- JSON-RPC has single path for method invocation
RSpec.describe API::Mcp, 'Call tool request', feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }
  let_it_be(:consumer_group) { create(:group) }
  let_it_be(:flow_project) { create(:project, group: consumer_group) }
  let_it_be(:flow) { create(:ai_catalog_flow, :public, project: flow_project) }

  let_it_be_with_reload(:execution_project) do
    create(:project, :repository, group: consumer_group, developers: user)
  end

  let_it_be(:group_consumer) { create(:ai_catalog_item_consumer, item: flow, group: consumer_group) }

  let_it_be(:project_consumer) do
    create(:ai_catalog_item_consumer, item: flow, project: execution_project,
      parent_item_consumer: group_consumer)
  end

  let(:params) do
    { jsonrpc: '2.0', method: 'tools/call', params: tool_params, id: '1' }
  end

  before_all do
    consumer_group.add_developer(user)
    execution_project.update!(duo_features_enabled: true, duo_remote_flows_enabled: true)
    flow_project.update!(duo_features_enabled: true)
  end

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(flow_project, :ai_catalog).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(execution_project, :ai_catalog).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(execution_project, :duo_workflow).and_return(true)
  end

  describe '#start_duo_session' do
    let(:tool_params) do
      {
        name: 'start_duo_session',
        arguments: {
          project_id: execution_project.id.to_s,
          ai_catalog_item_consumer_id: project_consumer.id,
          goal: 'Fix the flaky spec'
        }
      }
    end

    let(:workflow) { build(:duo_workflows_workflow, user: user, project: execution_project) }

    let(:execute_service) do
      instance_double(::Ai::Catalog::Flows::ExecuteService,
        execute: ServiceResponse.success(payload: { workflow: workflow, workload_id: 124 }))
    end

    it 'forces start_workflow, which the model never sends', :aggregate_failures do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(execute_workflow: true)
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.dig('result', 'isError')).to be(false)
    end

    # The path is the only reliable signal: the MCP handler re-dispatches with the original
    # env, so PATH_INFO still points at /api/v4/mcp when the route runs.
    it 'marks the session as started over MCP' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(source_type: :mcp)
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'records no client when the request names none' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(workflow_attributes: {})
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, headers: { 'User-Agent' => '' },
        as: :json

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'records the client from the User-Agent when _meta names none' do
      expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
        project: execution_project,
        current_user: user,
        params: hash_including(
          workflow_attributes: { source_client_name: 'Cursor', source_client_version: '1.0.0' }
        )
      ).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params,
        headers: { 'User-Agent' => 'Cursor/1.0.0 (darwin arm64)' }, as: :json

      expect(response).to have_gitlab_http_status(:ok)
    end

    context 'when the request names its client in _meta' do
      let(:tool_params) do
        super().merge(_meta: { 'io.modelcontextprotocol/clientInfo' => { name: 'claude-code', version: '2.1.0' } })
      end

      it 'records the client on the session' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: execution_project,
          current_user: user,
          params: hash_including(
            workflow_attributes: { source_client_name: 'claude-code', source_client_version: '2.1.0' }
          )
        ).and_return(execute_service)

        post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    it 'returns the session identifiers and a poll hint, not the raw workflow entity' do
      allow(::Ai::Catalog::Flows::ExecuteService).to receive(:new).and_return(execute_service)

      post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

      content = json_response.dig('result', 'structuredContent')
      expect(content.keys).to match_array(%w[workflow_id status workload_id poll_after_seconds web_url])
      expect(content['workload_id']).to eq(124)
      expect(content['web_url']).to eq(workflow.web_url)
      expect(json_response.dig('result', 'content', 0, 'text')).to include('get_duo_session')
    end

    context 'when the caller is not allowed to run the flow' do
      let_it_be(:outsider) { create(:user) }
      let_it_be(:outsider_token) { create(:oauth_access_token, user: outsider, scopes: [:mcp]) }

      it 'does not start a session' do
        expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        post api('/mcp', outsider, oauth_access_token: outsider_token), params: params, as: :json

        expect(json_response.dig('result', 'isError')).to be(true)
      end
    end

    context 'when the caller has read access but cannot run flows' do
      let_it_be(:reporter) { create(:user, reporter_of: execution_project) }
      let_it_be(:reporter_token) { create(:oauth_access_token, user: reporter, scopes: [:mcp]) }

      it 'refuses without creating a session, and names the role the caller needs', :aggregate_failures do
        expect(::Ai::Catalog::ExecuteWorkflowService).not_to receive(:new)
        expect(::Ci::Workloads::RunWorkloadService).not_to receive(:new)

        expect do
          post api('/mcp', reporter, oauth_access_token: reporter_token), params: params, as: :json
        end.to not_change { ::Ai::DuoWorkflows::Workflow.count }.and not_change { ::Ci::Pipeline.count }

        expect(json_response.dig('result', 'isError')).to be(true)
        expect(json_response.dig('result', 'content', 0, 'text'))
          .to include('Developer role', 'No session was started')
      end
    end

    context 'when a flow calls it with its composite identity token' do
      let_it_be(:flow_service_account) do
        create(:user, :service_account, composite_identity_enforced: true, developer_of: execution_project,
          provisioned_by_group: consumer_group)
      end

      let_it_be(:flow_token) do
        create(:oauth_access_token,
          organization: execution_project.organization,
          application: create(:doorkeeper_application),
          resource_owner: flow_service_account,
          expires_in: 1.hour,
          scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE, "user:#{user.id}"])
      end

      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, user: user, project: execution_project) }

      before do
        stub_feature_flags(ai_flow_trigger_chaining: consumer_group)

        # The calling workflow is authorized only for users entitled to the Duo Agent Platform.
        allow_next_found_instance_of(User) do |found_user|
          allow(found_user).to receive(:allowed_to_use?).and_call_original
          allow(found_user).to receive(:allowed_to_use?).with(:duo_agent_platform, anything).and_return(true)
        end
      end

      it 'starts the session as a child of the calling workflow' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: execution_project,
          current_user: user,
          params: hash_including(parent_workflow: parent_workflow)
        ).and_return(execute_service)

        post api('/mcp', oauth_access_token: flow_token), params: params, as: :json,
          headers: { 'X-Gitlab-Duo-Workflow-Id' => parent_workflow.id.to_s }

        expect(json_response.dig('result', 'isError')).to be(false)
      end

      it 'does not start a session without the calling workflow', :aggregate_failures do
        expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        post api('/mcp', oauth_access_token: flow_token), params: params, as: :json

        expect(json_response.dig('result', 'isError')).to be(true)
        expect(json_response.dig('result', 'content', 0, 'text'))
          .to include('An agent can only start a workflow from a workflow it is allowed to update')
      end
    end

    context 'when a GitLab flow is named instead of a catalog consumer' do
      let_it_be(:session) { create(:duo_workflows_workflow, user: user, project: execution_project) }

      let(:tool_params) do
        {
          name: 'start_duo_session',
          arguments: {
            project_id: execution_project.id.to_s,
            flow: 'developer/v1',
            goal: 'Fix the flaky spec'
          }
        }
      end

      before do
        stub_feature_flags(enforce_composite_identity_for_api_started_workflows: false)

        allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
          allow(service).to receive(:generate_workflow_token)
            .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))
        end

        allow(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).and_return(
          instance_double(::Ai::DuoWorkflows::StartWorkflowService,
            execute: ServiceResponse.success(payload: { workload_id: 124 }))
        )
      end

      it 'marks the session as started over MCP' do
        expect(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new)
          .with(hash_including(params: hash_including(source_type: :mcp)))
          .and_return(
            instance_double(::Ai::DuoWorkflows::CreateWorkflowService,
              execute: ServiceResponse.success(payload: { workflow: session }))
          )

        post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.dig('result', 'isError')).to be(false)
      end

      context 'when the request names its client in _meta' do
        let(:tool_params) do
          super().merge(_meta: { 'io.modelcontextprotocol/clientInfo' => { name: 'claude-code', version: '2.1.0' } })
        end

        it 'records the client on the session' do
          expect(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new)
            .with(hash_including(params: hash_including(
              source_type: :mcp, source_client_name: 'claude-code', source_client_version: '2.1.0'
            )))
            .and_return(
              instance_double(::Ai::DuoWorkflows::CreateWorkflowService,
                execute: ServiceResponse.success(payload: { workflow: session }))
            )

          post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

          expect(json_response.dig('result', 'isError')).to be(false)
        end
      end
    end

    context 'when the catalog consumer runs fix_pipeline' do
      let_it_be(:fix_pipeline_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'fix_pipeline/v1')
      end

      let_it_be(:fix_pipeline_consumer) do
        create(:ai_catalog_item_consumer, item: fix_pipeline_item, project: execution_project,
          parent_item_consumer: create(:ai_catalog_item_consumer, item: fix_pipeline_item, group: consumer_group))
      end

      let_it_be(:failing_merge_request) do
        create(:merge_request, source_project: execution_project, target_project: execution_project,
          source_branch: 'feature', target_branch: 'master')
      end

      let_it_be(:failed_pipeline) do
        create(:ci_pipeline, :failed, project: execution_project, ref: 'feature',
          sha: failing_merge_request.diff_head_sha)
      end

      let(:goal) { Gitlab::UrlBuilder.build(failed_pipeline) }
      let(:tool_params) do
        {
          name: 'start_duo_session',
          arguments: {
            project_id: execution_project.id.to_s, ai_catalog_item_consumer_id: fix_pipeline_consumer.id, goal: goal
          }
        }
      end

      it 'starts it on the branch of the pipeline in the goal, with the merge request it belongs to' do
        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: execution_project,
          current_user: user,
          params: hash_including(
            source_branch: 'feature',
            additional_context: array_including(
              hash_including('Category' => 'merge_request',
                'Content' => a_string_including("merge_requests/#{failing_merge_request.iid}"))
            )
          )
        ).and_return(execute_service)

        post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

        expect(json_response.dig('result', 'isError')).to be(false)
      end

      context 'when the goal is not a pipeline in the project' do
        let(:goal) { 'Fix the pipeline' }

        it 'refuses without starting a session, and says what the goal must be', :aggregate_failures do
          expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

          expect do
            post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json
          end.to not_change { ::Ai::DuoWorkflows::Workflow.count }

          expect(json_response.dig('result', 'isError')).to be(true)
          expect(json_response.dig('result', 'content', 0, 'text'))
            .to include('fix_pipeline/v1 fixes a pipeline', execution_project.full_path)
        end
      end
    end

    context 'when a foundational agent is named' do
      let(:agent) { 'analytics_agent/v1' }
      let(:session) do
        create(:duo_workflows_workflow, user: user, project: execution_project, workflow_definition: agent,
          goal: 'How many merge requests were merged last week?', environment: :ambient)
      end

      let(:tool_params) do
        {
          name: 'start_duo_session',
          arguments: { project_id: execution_project.id.to_s, agent: agent, goal: session.goal }
        }
      end

      let(:created_with) { {} }

      before do
        allow(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new) do |args|
          created_with.merge!(args[:params].to_h.symbolize_keys)
          instance_double(::Ai::DuoWorkflows::CreateWorkflowService,
            execute: ServiceResponse.success(payload: { workflow: session }))
        end
      end

      def start_session
        post api('/mcp', user, oauth_access_token: access_token), params: params, as: :json

        expect(response).to have_gitlab_http_status(:ok)
        json_response['result']
      end

      shared_examples 'a session started in CI' do
        before do
          stub_feature_flags(enforce_composite_identity_for_api_started_workflows: false)

          allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
            allow(service).to receive(:generate_workflow_token)
              .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))
          end
        end

        it 'starts it in a CI job', :aggregate_failures do
          expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).and_return(
            instance_double(::Ai::DuoWorkflows::StartWorkflowService,
              execute: ServiceResponse.success(payload: { workload_id: 124 }))
          )
          expect(::Ai::DuoWorkflows::ExecuteRunService).not_to receive(:new)

          result = start_session

          expect(result['isError']).to be(false)
          expect(result['structuredContent']).to include('workload_id' => 124)
          expect(result.dig('content', 0, 'text')).to include('It runs in a CI job')
        end

        it 'keeps the default privileges' do
          allow(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).and_return(
            instance_double(::Ai::DuoWorkflows::StartWorkflowService,
              execute: ServiceResponse.success(payload: { workload_id: 124 }))
          )

          start_session

          expect(created_with).not_to include(:agent_privileges, :pre_approved_agent_privileges)
        end
      end

      context 'when the agent needs no checkout' do
        it 'runs the first turn on Workhorse instead of in a CI job', :aggregate_failures do
          expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)
          expect(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async).with(session.id, nil, nil, {})

          result = start_session

          expect(result['isError']).to be(false)
          expect(result['structuredContent']).to include(
            'workflow_id' => session.id,
            'workload_id' => nil,
            'poll_after_seconds' => ::Mcp::Tools::DuoWorkflows::StartDuoSessionService::WORKHORSE_POLL_AFTER_SECONDS
          )
          expect(result.dig('content', 0, 'text')).to include('It runs without a CI job')
        end

        it 'gives the agent the privileges web chat gives it, and no service account', :aggregate_failures do
          start_session

          expect(created_with).to include(
            agent_privileges: [
              ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
              ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
              ::Ai::DuoWorkflows::Workflow::AgentPrivileges::START_FLOWS
            ],
            pre_approved_agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB],
            source_type: :mcp
          )
          expect(created_with[:service_account]).to be_nil
        end

        # The turn runs as the user, so the session needs no composite identity service account.
        it 'starts when API-started sessions require a composite identity service account' do
          allow(::Ai::Messaging::ServerSideTurnWorker).to receive(:perform_async)

          expect(start_session['isError']).to be(false)
        end

        context 'when the runtime refuses the session' do
          before do
            allow_next_instance_of(::Ai::DuoWorkflows::ExecuteRunService) do |service|
              allow(service).to receive(:execute)
                .and_return(ServiceResponse.error(message: 'The event is invalid for this workflow'))
            end
          end

          it 'reports the error' do
            expect(::Ai::Messaging::ServerSideTurnWorker).not_to receive(:perform_async)

            result = start_session

            expect(result['isError']).to be(true)
            expect(result.dig('content', 0, 'text')).to include('The event is invalid for this workflow')
          end
        end

        context 'when mcp_duo_agent_sessions_on_workhorse is disabled' do
          before do
            stub_feature_flags(mcp_duo_agent_sessions_on_workhorse: false)
          end

          it_behaves_like 'a session started in CI'
        end
      end

      context 'when the agent needs a checkout' do
        let(:agent) { 'orbit_agent/v1' }

        it_behaves_like 'a session started in CI'
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
