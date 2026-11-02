# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::DuoWorkflows::AgentWorkflows, feature_category: :duo_agent_platform do
  include ProjectForksHelper

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :repository, group: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:ai_workflows_oauth_token) do
    create(:oauth_access_token, user: user, scopes: [:ai_workflows])
  end

  let_it_be(:auth_response) { Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [group.id]) }
  let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }
  let(:workflow_definition) { 'software_development' }
  let(:allow_agent_to_request_user) { false }
  let(:path) { "/ai/duo_workflows/agent_workflows" }
  let(:params) do
    {
      project_id: project.id,
      workflow_definition: workflow_definition,
      allow_agent_to_request_user: allow_agent_to_request_user
    }
  end

  before_all do
    group.add_developer(user)
    project.add_member(service_account, Gitlab::Access::DEVELOPER)
  end

  before do
    # Requests below do not come from a running workflow; chaining is covered in its own context.
    stub_feature_flags(ai_flow_trigger_chaining: false)
    # The precondition check runs on by default; make the factory project look runner-ready.
    stub_duo_runner_available(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :duo_workflow).and_return(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)

    allow_any_instance_of(User).to receive(:allowed_to_use).and_return(auth_response) # rubocop:disable RSpec/AnyInstanceOf -- not the next instance
    allow_next_instance_of(::Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService) do |service|
      allow(service).to receive(:execute).and_return(
        ServiceResponse.success(
          payload: {
            oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'token-12345')
          }
        )
      )
    end

    ::Ai::Setting.for_organization(project.organization)
      .update!(duo_workflow_service_account_user_id: service_account.id)
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor).and_call_original
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
                                         .with(user).and_return(service_account)
    allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
                                         .with(service_account).and_return(service_account)
    project.update!(allow_composite_identities_to_run_pipelines: true)
    project.reload
  end

  describe 'POST /ai/duo_workflows/agent_workflows' do
    before do
      allow_next_instance_of(Ai::UsageQuotaService) do |instance|
        allow(instance).to receive(:execute).and_return(ServiceResponse.success)
      end
    end

    context 'when identity verification is required' do
      before do
        allow_next_found_instance_of(User) do |found_user|
          allow(found_user).to receive(:dap_identity_verification_required?).and_return(true)
        end
      end

      it 'names identity verification in the error', :aggregate_failures do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Identity verification is required')
      end
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post api(path), params: params

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when authenticated as a regular user' do
      before do
        allow(Gitlab::AiGateway).to receive(:public_headers)
          .with(user: user, ai_feature_name: :duo_workflow, unit_primitive_name: :duo_agent_platform,
            governing_namespace_id: user.governing_namespace(project).id,
            organization_id: user.governing_namespace(project).organization_id,
            subject: user
          )
          .and_return({ 'x-gitlab-enabled-feature-flags' => 'test-feature' })
      end

      it 'creates a workflow' do
        expect do
          post api(path, user), params: params
          expect(response).to have_gitlab_http_status(:created)
        end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)

        created_workflow = Ai::DuoWorkflows::Workflow.last
        expect(json_response['id']).to eq(created_workflow.id)
        expect(created_workflow.workflow_definition).to eq(workflow_definition)
        expect(created_workflow.allow_agent_to_request_user).to eq(allow_agent_to_request_user)
      end
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      before do
        allow(Gitlab::AiGateway).to receive(:public_headers)
          .with(user: user, ai_feature_name: :duo_workflow, unit_primitive_name: :duo_agent_platform,
            governing_namespace_id: user.governing_namespace(project).id,
            organization_id: user.governing_namespace(project).organization_id,
            subject: user)
          .and_return({})
      end

      it 'creates the workflow (agent-initiated foundational flow)' do
        expect do
          post api(path, oauth_access_token: ai_workflows_oauth_token), params: params
          expect(response).to have_gitlab_http_status(:created)
        end.to change { Ai::DuoWorkflows::Workflow.count }.by(1)
      end
    end

    context 'with a catalog workflow' do
      let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
      let_it_be(:consumer) do
        create(:ai_catalog_item_consumer, item: flow, project: project, pinned_version_prefix: nil)
      end

      let(:input_required_workflow) do
        create(:duo_workflows_workflow, user: user, project: project, status: 6,
          ai_catalog_item: flow, ai_catalog_item_version: flow.latest_version)
      end

      context 'when workflow execution returns error' do
        before do
          allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Something went wrong', reason: :validation_error)
            )
          end
        end

        it 'returns 400' do
          post api(path, user), params: params.merge(ai_catalog_item_consumer_id: consumer.id)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('Something went wrong')
        end
      end

      context 'when workflow execution returns an unprocessable_entity error' do
        before do
          allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(message: ['No eligible runner'], http_status: :unprocessable_entity) # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
            )
          end
        end

        it 'returns 422' do
          post api(path, user), params: params.merge(ai_catalog_item_consumer_id: consumer.id)

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
        end
      end

      context 'when workflow execution returns a :repository_empty error' do
        let(:approved_message) do
          "This flow couldn't start because the project doesn't have a repository yet. " \
            'Add a repository to get started with flows.'
        end

        before do
          allow_next_instance_of(::Ai::Catalog::Flows::ExecuteService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(
                message: [approved_message],
                http_status: :unprocessable_entity, # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
                reason: :repository_empty
              )
            )
          end
        end

        it 'returns 422 with the approved message and reason' do
          post api(path, user), params: params.merge(ai_catalog_item_consumer_id: consumer.id)

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to eq(approved_message)
          expect(json_response['reason']).to eq('repository_empty')
        end
      end
    end

    context 'without a catalog workflow when workflow creation fails with error status' do
      before do
        allow_next_instance_of(::Ai::DuoWorkflows::CreateWorkflowService) do |svc|
          response = instance_double(ServiceResponse)
          allow(response).to receive(:error?).and_return(false)
          allow(response).to receive(:[]).with(:status).and_return(:error)
          allow(response).to receive(:[]).with(:message).and_return('Workflow creation failed')
          allow(svc).to receive(:execute).and_return(response)
        end
      end

      it 'returns 400' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('Workflow creation failed')
      end
    end

    context 'without a catalog workflow when workflow creation returns an unprocessable_entity error' do
      before do
        allow_next_instance_of(::Ai::DuoWorkflows::CreateWorkflowService) do |svc|
          # rubocop:disable Gitlab/ServiceResponse -- Preserve the actual behavior of the service response.
          allow(svc).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'No eligible runner', http_status: :unprocessable_entity))
          # rubocop:enable Gitlab/ServiceResponse
        end
      end

      it 'returns 422' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to include('No eligible runner')
      end
    end

    context 'when agent_privileges is provided' do
      before do
        allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
      end

      it 'ignores the parameter and creates the workflow with default privileges' do
        post api(path, user), params: params.merge(
          agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES]
        )

        expect(response).to have_gitlab_http_status(:created)

        created_workflow = Ai::DuoWorkflows::Workflow.last
        expect(created_workflow.agent_privileges).to match_array(
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::DEFAULT_PRIVILEGES
        )
      end
    end

    context 'when pre_approved_agent_privileges is provided' do
      before do
        allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
      end

      it 'ignores the parameter and creates workflow with the database default pre-approved privileges' do
        post api(path, user), params: params.merge(
          pre_approved_agent_privileges: [::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES]
        )

        expect(response).to have_gitlab_http_status(:created)

        created_workflow = Ai::DuoWorkflows::Workflow.last
        # pre_approved_agent_privileges is not accepted by this endpoint, so the passed value is ignored
        # and the DB default [READ_WRITE_FILES, READ_ONLY_GITLAB] is used instead
        expect(created_workflow.pre_approved_agent_privileges).to match_array([
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES,
          ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB
        ])
      end
    end

    context 'when workflow creation fails' do
      context 'when user is not a developer' do
        let(:user) { create(:user, guest_of: project) }

        it_behaves_like 'workflow access is forbidden'
      end

      context 'when duo_features_enabled is off' do
        before do
          project.project_setting.update!(duo_features_enabled: false)
          project.reload
        end

        it_behaves_like 'workflow access is forbidden'
      end

      context 'when there are not enough credits' do
        before do
          allow_next_instance_of(Ai::UsageQuotaService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(message: "Usage quota exceeded", reason: :usage_quota_exceeded)
            )
          end
        end

        it_behaves_like 'workflow access is forbidden'
      end
    end

    it_behaves_like 'start workflow execution'

    it_behaves_like 'foundational flow workflow creation'

    it_behaves_like 'ai catalog item consumer workflow execution'

    it_behaves_like 'ai catalog item version workflow creation'

    it_behaves_like 'issue and merge request association for workflows'

    it_behaves_like 'container resolution for workflows'

    context 'when agent sends project path with issue IID (agent-initiated linkage)' do
      let(:agent_params) do
        {
          project_id: project.full_path,
          workflow_definition: 'developer/v1',
          goal: 'implement feature X',
          issue_id: issue.iid,
          environment: 'ambient'
        }
      end

      before do
        allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
      end

      it 'creates workflow linked to the issue with a system note', :aggregate_failures do
        expect(SystemNoteService).to receive(:agent_session_started).with(
          issue,
          project,
          be_a(Integer),
          user,
          anything
        )

        post api(path, user), params: agent_params

        expect(response).to have_gitlab_http_status(:created)

        created_workflow = Ai::DuoWorkflows::Workflow.last
        expect(created_workflow.project).to eq(project)
        expect(created_workflow.issue).to eq(issue)
        expect(created_workflow.merge_request).to be_nil
        expect(created_workflow.environment).to eq('ambient')
      end
    end

    context 'when service account is resolved' do
      let_it_be(:foundational_flow_group) { create(:group) }
      let(:foundational_params) do
        {
          project_id: foundational_flow_project.id,
          workflow_definition: 'fix_pipeline/v1',
          goal: 'Fix the pipeline',
          start_workflow: true
        }
      end

      let_it_be(:foundational_flow_service_account) do
        create(:user, :service_account,
          composite_identity_enforced: true,
          provisioned_by_group: foundational_flow_group
        )
      end

      let_it_be_with_reload(:foundational_flow_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'fix_pipeline/v1')
      end

      let_it_be(:foundational_flow_consumer) do
        create(:ai_catalog_item_consumer,
          item: foundational_flow_item,
          group: foundational_flow_group,
          service_account: foundational_flow_service_account
        )
      end

      let_it_be_with_reload(:foundational_flow_project) do
        create(:project, :repository, group: foundational_flow_group, developers: user)
      end

      let_it_be(:foundational_flow_project_consumer) do
        create(:ai_catalog_item_consumer,
          item: foundational_flow_item,
          project: foundational_flow_project,
          parent_item_consumer: foundational_flow_consumer
        )
      end

      let_it_be(:foundational_flow_enabled) do
        create(:ai_catalog_enabled_foundational_flow, :for_project,
          project: foundational_flow_project,
          catalog_item: foundational_flow_item)
      end

      before_all do
        foundational_flow_group.add_developer(user)
        foundational_flow_project.update!(duo_features_enabled: true, duo_remote_flows_enabled: true,
          duo_foundational_flows_enabled: true)
        foundational_flow_item.latest_version.update!(release_date: Time.current)
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
        allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                              .with(foundational_flow_project, :duo_workflow).and_return(true)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                              .with(foundational_flow_project, :foundational_flows).and_return(true)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                                              .with(foundational_flow_project, :ai_catalog).and_return(true)
        allow(::Ai::Catalog::FoundationalFlow.fix_pipeline_v1).to receive(:catalog_item)
          .and_return(foundational_flow_item)
        allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:generate_token).and_return(
            ServiceResponse.success(payload: { token: "an-encrypted-token" })
          )
        end
        allow_next_instance_of(::Ai::DuoWorkflows::CreateOauthAccessTokenService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(
              payload: {
                oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth_token')
              }
            )
          )
        end
        allow_next_instance_of(::Ai::Catalog::ItemConsumers::ResolveServiceAccountService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(payload: { service_account: foundational_flow_service_account })
          )
        end
        allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |svc|
          allow(svc).to receive(:execute)
                          .and_return(ServiceResponse.success(payload: { workload_id: 1 }))
        end
      end

      def expect_start_workflow_service_with(**expected_params)
        expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).with(
          hash_including(params: hash_including(**expected_params))
        ).and_wrap_original do |original, **kwargs|
          original.call(**kwargs).tap do |instance|
            allow(instance).to receive(:execute).and_return(ServiceResponse.success(payload: { workload_id: 1 }))
          end
        end
      end

      it 'passes the resolved service_account to StartWorkflowService' do
        expect_start_workflow_service_with(service_account: foundational_flow_service_account)

        post api(path, user), params: foundational_params

        expect(response).to have_gitlab_http_status(:created)
      end

      # A chat-started run posts `fix_pipeline/v1`; the flag decides which flow config
      # actually runs, through FoundationalFlowStartParamsResolver in start_workflow_params.
      context 'when fix_pipeline_experimental is disabled' do
        before do
          stub_feature_flags(fix_pipeline_experimental: false)
        end

        it 'passes the v1 flow routing params to StartWorkflowService' do
          expect_start_workflow_service_with(
            flow_config_id: 'fix_pipeline',
            flow_config_schema_version: 'v1',
            flow_version: ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1.flow_version
          )

          post api(path, user), params: foundational_params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when fix_pipeline_experimental is enabled for the project' do
        before do
          stub_feature_flags(fix_pipeline_experimental: foundational_flow_project)
        end

        it 'routes the run to fix_pipeline/experimental' do
          expect_start_workflow_service_with(
            flow_config_id: 'fix_pipeline',
            flow_config_schema_version: 'experimental',
            flow_version: ::Ai::Catalog::FoundationalFlow::DEFAULT_FLOW_VERSION
          )

          post api(path, user), params: foundational_params

          expect(response).to have_gitlab_http_status(:created)
        end
      end

      context 'when StartWorkflowService returns a :repository_empty error' do
        before do
          allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |svc|
            allow(svc).to receive(:execute).and_return(
              ServiceResponse.error(
                message: 'Repository is empty',
                reason: :repository_empty
              )
            )
          end
        end

        it 'returns 422 with the reason and message' do
          post api(path, user), params: foundational_params

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message']).to eq('Repository is empty')
          expect(json_response['reason']).to eq('repository_empty')
        end
      end
    end

    # An agent caller must not reach the client-executed branch, whatever it passes.
    context 'when an agent delegates a foundational flow to a group' do
      let_it_be(:delegated_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1')
      end

      let(:params) do
        { namespace_id: group.id, workflow_definition: 'developer/v1', goal: 'Do the thing' }
      end

      before do
        allow(::Ai::Catalog::FoundationalFlow.developer_v1).to receive(:catalog_item)
          .and_return(delegated_item)
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_call_original
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :foundational_flows).and_return(true)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, group).and_return(true)
      end

      it 'stays catalog-governed even without start_workflow' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'says the flow is not enabled for the group' do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item_consumer, group).and_return(true)

        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('403 Forbidden - This flow is not enabled for this project or group')
      end
    end

    context 'when the caller sends an environment' do
      let(:params) { super().merge(environment: 'ambient') }

      it 'stores it exactly as sent' do
        post api(path, user), params: params

        expect(response).to have_gitlab_http_status(:created)
        expect(Ai::DuoWorkflows::Workflow.last.environment).to eq('ambient')
      end
    end

    describe 'goal validation' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be(:fork_merge_request) do
        create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
      end

      let_it_be(:bl_security_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'bl_security/experimental')
      end

      let_it_be(:code_review_item) do
        create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'code_review/v1')
      end

      let_it_be(:bl_security_consumer) { create(:ai_catalog_item_consumer, item: bl_security_item, project: project) }
      let_it_be(:code_review_consumer) { create(:ai_catalog_item_consumer, item: code_review_item, project: project) }
      let(:execute_allowed) { true }
      let(:bl_params) { { project_id: project.id, workflow_definition: 'bl_security/experimental' } }

      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :execute_ai_catalog_item, anything).and_return(execute_allowed)
        allow_next_instance_of(::Ai::DuoWorkflows::FlowExecutionAuthorizer) do |authorizer|
          allow(authorizer).to receive(:execute).and_return(
            execute_allowed ? ServiceResponse.success(payload: {}) : ServiceResponse.error(message: 'Denied')
          )
        end
      end

      it 'refuses an unknown merge request IID' do
        post api(path, user), params: bl_params.merge(goal: non_existing_record_iid)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('Merge request not found')
      end

      it 'refuses a merge request that only deletes files' do
        MergeRequestDiffFile.where(merge_request_diff_id: merge_request.merge_request_diff.id)
          .update_all(deleted_file: true)

        post api(path, user), params: bl_params.merge(goal: merge_request.iid)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('no added or modified files')
      end

      it 'checks out the merge request source branch when the caller names none' do
        workflow = create(:duo_workflows_workflow, project: project, user: user)
        allow_next_instance_of(::Ai::DuoWorkflows::CreateWorkflowService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workflow: workflow }))
        end
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})
        allow_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
          allow(service).to receive_messages(
            generate_oauth_token_with_composite_identity_support: ServiceResponse.success(
              payload: { oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'token') }
            ),
            generate_workflow_token: ServiceResponse.success(payload: { token: 'workflow-token' }),
            duo_agent_platform_feature_setting: nil
          )
        end

        expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new)
          .with(hash_including(params: hash_including(source_branch: merge_request.source_branch)))
          .and_return(instance_double(::Ai::DuoWorkflows::StartWorkflowService,
            execute: ServiceResponse.success(payload: { workload_id: 1 })))

        post api(path, user), params: bl_params.merge(goal: merge_request.iid, start_workflow: true)

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'when the caller cannot execute the flow' do
        let(:execute_allowed) { false }

        it 'returns the authorization error before validating a consumer goal' do
          post api(path, user), params: {
            project_id: project.id, ai_catalog_item_consumer_id: bl_security_consumer.id, goal: fork_merge_request.iid
          }

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['message']).to include('You have insufficient permissions')
        end

        it 'returns the authorization error before validating a goal by name' do
          post api(path, user), params: bl_params.merge(goal: fork_merge_request.iid)

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).not_to include('forks')
        end
      end

      it 'refuses a goal the flow rejects when started through a consumer' do
        expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

        post api(path, user), params: {
          project_id: project.id, ai_catalog_item_consumer_id: bl_security_consumer.id, goal: fork_merge_request.iid
        }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('Merge requests from forks are not scanned')
      end

      it 'refuses a goal the flow rejects when started by name' do
        expect do
          post api(path, user), params: {
            project_id: project.id, workflow_definition: 'bl_security/experimental', goal: fork_merge_request.iid
          }
        end.not_to change { Ai::DuoWorkflows::Workflow.count }

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('Merge requests from forks are not scanned')
      end

      it 'does not validate other flows, with the business logic flag off' do
        stub_feature_flags(bl_security_analyzer: false)
        goal = Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request)
        fake_workflow = build(:duo_workflows_workflow, id: 180, user: user, project: project)

        expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new).with(
          project: project,
          current_user: user,
          params: hash_including(item_consumer: code_review_consumer, user_prompt: goal)
        ).and_return(
          instance_double(
            Ai::Catalog::Flows::ExecuteService,
            execute: ServiceResponse.success(payload: { workflow: fake_workflow })
          )
        )

        post api(path, user), params: {
          project_id: project.id,
          ai_catalog_item_consumer_id: code_review_consumer.id,
          goal: goal
        }

        expect(response).to have_gitlab_http_status(:created)
      end
    end

    context 'when workflow access is forbidden' do
      let(:user) { create(:user, guest_of: project) }

      it_behaves_like 'workflow access is forbidden'
    end

    context 'when the request comes from a running workflow' do
      let_it_be(:parent_workflow) { create(:duo_workflows_workflow, user: user, project: project) }
      let(:headers) { { 'X-Gitlab-Duo-Workflow-Id' => parent_workflow.id.to_s } }

      before do
        allow(Gitlab::AiGateway).to receive(:public_headers).and_return({})
      end

      def post_workflow(headers: self.headers, request_params: params)
        post api(path, user), params: request_params, headers: headers
      end

      context 'when ai_flow_trigger_chaining is enabled' do
        before do
          stub_feature_flags(ai_flow_trigger_chaining: group)
        end

        it 'creates the workflow as a child of the parent workflow', :aggregate_failures do
          expect { post_workflow }.to change { parent_workflow.child_workflows.count }.by(1)

          expect(response).to have_gitlab_http_status(:created)

          child = Ai::DuoWorkflows::Workflow.find(json_response['id'])
          expect(child.parent_workflow).to eq(parent_workflow)
          expect(child).to be_triggered_by_flow
        end

        context 'when the header is missing' do
          it 'rejects the request' do
            expect { post_workflow(headers: {}) }.not_to change { Ai::DuoWorkflows::Workflow.count }

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end

        context 'when the header references a workflow that does not exist' do
          it 'rejects the request' do
            post_workflow(headers: { 'X-Gitlab-Duo-Workflow-Id' => non_existing_record_id.to_s })

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end

        context 'when the header references a workflow the user cannot update' do
          let_it_be(:other_user) { create(:user, developer_of: project) }
          let_it_be(:other_workflow) { create(:duo_workflows_workflow, user: other_user, project: project) }

          it 'rejects the request' do
            expect { post_workflow(headers: { 'X-Gitlab-Duo-Workflow-Id' => other_workflow.id.to_s }) }
              .not_to change { Ai::DuoWorkflows::Workflow.count }

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end

        context 'when the chain is already at the depth limit' do
          before do
            stub_const("#{Ai::FlowTriggers::CallerContext}::MAX_TRIGGER_DEPTH", 1)
          end

          it 'rejects the request' do
            post_workflow

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(json_response['message']).to include('workflow chain is too deep')
          end
        end

        context 'when the parent has already started the maximum number of workflows' do
          before do
            stub_const("#{Ai::FlowTriggers::CallerContext}::MAX_CHILD_WORKFLOWS_PER_PARENT", 1)
            create(:duo_workflows_workflow, user: user, project: project, trigger_source: :flow,
              parent_workflow: parent_workflow)
          end

          it 'rejects the request' do
            post_workflow

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(json_response['message']).to include('workflow started too many workflows')
          end
        end

        context 'when the chain was started autonomously' do
          let_it_be(:autonomous_workflow) do
            create(:duo_workflows_workflow, user: user, project: project, trigger_source: :system)
          end

          it 'rejects the request' do
            post_workflow(headers: { 'X-Gitlab-Duo-Workflow-Id' => autonomous_workflow.id.to_s })

            expect(response).to have_gitlab_http_status(:forbidden)
            expect(json_response['message']).to include('workflow chain was not started by a human user')
          end
        end

        context 'with a catalog workflow' do
          let_it_be(:flow) { create(:ai_catalog_flow, :public, project: project) }
          let_it_be(:consumer) do
            create(:ai_catalog_item_consumer, item: flow, project: project, pinned_version_prefix: nil)
          end

          it 'passes the parent workflow to the flow execution' do
            expect(::Ai::Catalog::Flows::ExecuteService).to receive(:new)
              .with(project: project, current_user: user, params: hash_including(parent_workflow: parent_workflow))
              .and_return(instance_double(::Ai::Catalog::Flows::ExecuteService,
                execute: ServiceResponse.error(message: 'stop')))

            post_workflow(request_params: params.merge(ai_catalog_item_consumer_id: consumer.id))
          end

          it 'rejects the request when the header is missing' do
            expect(::Ai::Catalog::Flows::ExecuteService).not_to receive(:new)

            post_workflow(headers: {}, request_params: params.merge(ai_catalog_item_consumer_id: consumer.id))

            expect(response).to have_gitlab_http_status(:forbidden)
          end
        end
      end

      context 'when ai_flow_trigger_chaining is disabled' do
        it 'ignores the header and creates a workflow without a parent', :aggregate_failures do
          post_workflow

          expect(response).to have_gitlab_http_status(:created)
          expect(Ai::DuoWorkflows::Workflow.find(json_response['id']).parent_workflow).to be_nil
        end
      end
    end
  end
end
