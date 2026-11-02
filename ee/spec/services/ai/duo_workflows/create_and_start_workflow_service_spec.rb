# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::CreateAndStartWorkflowService, feature_category: :duo_agent_platform do
  subject(:result) { service.execute }

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:current_user) { create(:user, developer_of: project) }
  let_it_be(:oauth_token) { create(:oauth_access_token, user: current_user, scopes: [:api]) }
  let_it_be(:group_level_service_account) do
    create(:user, :service_account) do |user|
      create(:user_detail, user: user, provisioned_by_group: group)
    end
  end

  let_it_be(:catalog_item) do
    create(:ai_catalog_item, :with_foundational_flow_reference, :public, :flow, project: project)
  end

  let_it_be(:group_catalog_item_consumer) do
    create(:ai_catalog_item_consumer, group: group, item: catalog_item, service_account: group_level_service_account)
  end

  let_it_be(:project_catalog_item_consumer) do
    create(
      :ai_catalog_item_consumer,
      project: project,
      item: catalog_item,
      service_account: nil,
      parent_item_consumer: group_catalog_item_consumer
    )
  end

  let_it_be(:project_enabled_flow) do
    create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: catalog_item)
  end

  let(:goal) { 'Custom goal' }
  let(:source_branch) { 'feature/add-workflow' }

  let(:workflow_definition) do
    ::Ai::Catalog::FoundationalFlow.new(
      display_name: catalog_item.foundational_flow_reference,
      foundational_flow_reference: catalog_item.foundational_flow_reference
    )
  end

  let(:service) do
    described_class.new(
      container: project,
      current_user: current_user,
      goal: goal,
      source_branch: source_branch,
      workflow_definition: workflow_definition
    )
  end

  let(:workflow_service_token_result) do
    ServiceResponse.success(
      payload: { token: 'foo' }
    )
  end

  let(:workflow_oauth_token_result) do
    ServiceResponse.success(
      payload: { oauth_access_token: oauth_token }
    )
  end

  let(:resolve_service_account_result) do
    ServiceResponse.success(
      payload: { service_account: group_level_service_account }
    )
  end

  shared_examples 'failure' do |reason, message|
    it 'does not create a workload to execute workflow', :aggregate_failures do
      expect(result).to be_error
      expect(result.message).to eq(message)
      expect(result.reason).to eq(reason)
    end
  end

  shared_examples 'success' do
    it 'creates the workflow and starts a workload to execute with the correct definition', :aggregate_failures do
      expect(result).to be_success

      workflow = result.payload[:workflow]
      workload_id = result.payload[:workload_id]

      expect(workflow).to be_a(Ai::DuoWorkflows::Workflow)
      expect(workflow.source_type).to eq('flow_trigger')

      expect(workload_id).not_to be_nil
      expect(workflow.workflows_workloads.first).to have_attributes(project_id: project.id, workload_id: workload_id)

      workload = Ci::Workloads::Workload.find_by(id: workload_id)
      expect(workload.branch_name).to start_with('refs/workloads/')
      expect(workload.pipeline.user).to eq(group_level_service_account)
    end
  end

  before do
    # Defaults enabled for unstubbed specs; some examples below re-stub this
    # service in a way that drops the oauth-token stub, hitting the real
    # JWT-issuance path with no Cloud Connector key configured.
    stub_feature_flags(duo_workflow_use_token_issuer: false)
    # The precondition check runs on by default; make the factory project look runner-ready.
    stub_duo_runner_available(true)
    # Stub every WorkflowContextGenerationService instance rather than just the
    # next one, so construction order cannot bypass the stub.
    allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new) do |*_args, **_kwargs|
      instance_double(
        ::Ai::DuoWorkflows::WorkflowContextGenerationService,
        generate_workflow_token: workflow_service_token_result,
        generate_oauth_token_with_composite_identity_support: workflow_oauth_token_result,
        duo_agent_platform_feature_setting: nil
      )
    end

    allow_next_instance_of(::Ai::Catalog::ItemConsumers::ResolveServiceAccountService) do |service|
      allow(service).to receive(:execute).and_return(resolve_service_account_result)
    end

    # Membership and foundational-flow-param resolution run inside the start; stub
    # both so the spec stays isolated.
    allow_next_instance_of(::Ai::ServiceAccountMemberAddService) do |instance|
      allow(instance).to receive(:execute).and_return(ServiceResponse.success)
    end

    allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return(
      { flow_config_id: 'flow-config-id', flow_config_schema_version: 'v1', flow_version: '1.0.0' }
    )

    allow_next_instance_of(Ai::UsageQuotaService) do |instance|
      allow(instance).to receive(:execute).and_return(
        ServiceResponse.success
      )
    end

    allow(::Ai::DuoWorkflow).to receive(:available?).and_return(true)

    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(current_user, :create_duo_workflow_for_ci, project).and_return(true)
    allow(Ability).to receive(:allowed?).with(current_user, :execute_duo_workflow_in_ci, anything).and_return(true)
    allow(Ability).to receive(:allowed?).with(current_user, :read_ai_catalog_item_consumer, anything).and_return(true)

    project.project_setting.update!(
      duo_foundational_flows_enabled: true,
      duo_features_enabled: true,
      duo_remote_flows_enabled: true
    )

    project.add_member(group_level_service_account, :developer)
  end

  context 'with a parent workflow' do
    let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: current_user) }

    let(:service) do
      described_class.new(
        container: project,
        current_user: current_user,
        goal: goal,
        source_branch: source_branch,
        workflow_definition: workflow_definition,
        parent_workflow: parent_workflow
      )
    end

    it 'creates the workflow under the parent and returns the chain error reason', :aggregate_failures do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new)
        .with(hash_including(params: hash_including(parent_workflow: parent_workflow)))
        .and_return(instance_double(::Ai::DuoWorkflows::CreateWorkflowService,
          execute: ServiceResponse.error(message: 'workflow chain is too deep',
            payload: { reason: :trigger_depth_exceeded })))

      expect(result).to be_error
      expect(result.reason).to eq(:trigger_depth_exceeded)
    end
  end

  context 'with a source type' do
    let(:service) do
      described_class.new(
        container: project,
        current_user: current_user,
        goal: goal,
        source_branch: source_branch,
        workflow_definition: workflow_definition,
        source_type: :work_item_workplan
      )
    end

    it 'creates the workflow with the given source type' do
      expect(::Ai::DuoWorkflows::CreateWorkflowService).to receive(:new)
        .with(hash_including(params: hash_including(source_type: :work_item_workplan)))
        .and_call_original

      result
    end
  end

  context 'when workflow definition is not provided' do
    let(:workflow_definition) { nil }

    include_examples 'failure', :invalid_workflow_definition, 'Workflow definition cannot be blank'
  end

  context 'when source branch is not provided' do
    let(:source_branch) { nil }

    include_examples 'failure', :invalid_source_branch, 'Source branch cannot be blank'
  end

  # A token failure surfaces after creation, so the session is created and then
  # dropped (the same cleanup as any post-create start failure).
  context 'when workflow token could not be generated' do
    let(:workflow_service_token_result) do
      ServiceResponse.error(message: 'Could not create workflow token')
    end

    it 'creates then drops the session and surfaces the token reason', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_duo_workflow_token)

      workflow = Ai::DuoWorkflows::Workflow.last
      expect(workflow.status_name).to eq(:failed)
      expect(workflow).to be_status_terminal
    end
  end

  context 'when oauth token could not be generated' do
    let(:workflow_oauth_token_result) do
      ServiceResponse.error(message: 'Could not create workflow token')
    end

    it 'creates then drops the session and surfaces the token reason', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_oauth_token)

      workflow = Ai::DuoWorkflows::Workflow.last
      expect(workflow.status_name).to eq(:failed)
      expect(workflow).to be_status_terminal
    end
  end

  context 'when oauth token generation raises' do
    before do
      context_service = instance_double(::Ai::DuoWorkflows::WorkflowContextGenerationService)
      allow(context_service).to receive(:generate_oauth_token_with_composite_identity_support)
        .and_raise(ActiveRecord::RecordInvalid)
      allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(context_service)
    end

    it 'returns the token reason instead of raising, and drops the session', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_oauth_token)
      expect(Ai::DuoWorkflows::Workflow.last.status_name).to eq(:failed)
    end
  end

  context 'when flow is not enabled in the catalog item consumers' do
    context 'when flow does not have a catalog item' do
      before do
        allow(workflow_definition).to receive(:foundational_flow_reference).and_return(nil)
      end

      include_examples 'failure', :flow_not_enabled, 'Workflow not enabled for this project/namespace'
    end

    context 'when foundational flows are disabled' do
      before do
        allow(project).to receive(:duo_foundational_flows_enabled).and_return(false)
      end

      include_examples 'failure', :flow_not_enabled, 'Workflow not enabled for this project/namespace'
    end

    context 'when the flow is disabled' do
      before do
        allow(project).to receive(:enabled_flow_catalog_item_ids).and_return([])
      end

      include_examples 'failure', :flow_not_enabled, 'Workflow not enabled for this project/namespace'
    end
  end

  context 'when service account could not be resolved' do
    let(:resolve_service_account_result) do
      ServiceResponse.error(message: 'Could not resolve service account')
    end

    include_examples 'failure', :invalid_service_account, 'Could not resolve the service account for this flow'
  end

  context 'when usage quota is exceeded' do
    before do
      allow_next_instance_of(Ai::UsageQuotaService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.error(message: "Usage quota exceeded", reason: :usage_quota_exceeded)
        )
      end
    end

    include_examples 'failure', :usage_quota_exceeded, 'Usage quota exceeded'
  end

  context 'when namespace is missing' do
    before do
      allow_next_instance_of(Ai::UsageQuotaService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.error(message: "Namespace is required", reason: :namespace_missing)
        )
      end
    end

    it 'returns an error with actionable namespace message', :aggregate_failures do
      expect(result).to be_error
      expect(result.message).to include(current_user.to_reference)
      expect(result.message).to include('default GitLab Duo namespace')
      expect(result.message).to include('preferences')
      expect(result.reason).to eq(:namespace_missing)
    end
  end

  context 'when workflow fails to start' do
    before do
      allow_next_instance_of(Ai::DuoWorkflows::StartWorkflowService) do |instance|
        allow(instance).to receive(:execute).and_return(
          ServiceResponse.error(message: 'Random failure', reason: :random_reason)
        )
      end
    end

    include_examples 'failure', :random_reason, 'Random failure'

    # Anything reading status to decide whether a flow is live would otherwise treat this
    # workflow as running until CleanStuckWorkflowsService reaps it half an hour later.
    it 'does not leave the workflow looking live' do
      service.execute

      workflow = Ai::DuoWorkflows::Workflow.last
      expect(workflow.status_name).to eq(:failed)
      expect(workflow).to be_status_terminal
      expect(workflow.drop_reason).to eq('start_failed')
    end

    # Dropping here removes the workflow from CleanStuckWorkflowsService's scope, so the
    # terminal event it used to emit half an hour later has to be emitted here or the flow
    # goes missing from the completion rate, which reads this event for dropped_event_at.
    it 'emits the terminal event the reaper used to emit' do
      expect { service.execute }.to trigger_internal_events('agent_platform_session_dropped')
        .with(category: described_class.name, user: current_user, project: project,
          additional_properties: { drop_reason: 'start_failed' })
    end

    it 'records the audit event the reaper used to record' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: described_class::DROP_AUDIT_EVENT_NAME,
          author: current_user,
          scope: project,
          target: an_instance_of(Ai::DuoWorkflows::Workflow),
          message: described_class::DROP_AUDIT_EVENT_MESSAGE
        )
      ).and_call_original

      service.execute
    end
  end

  # A composite identity conflict raises out of the start rather than returning an error,
  # so the error-response path alone does not cover this.
  context 'when starting the workflow raises' do
    before do
      allow_next_instance_of(Ai::DuoWorkflows::StartWorkflowService) do |instance|
        allow(instance).to receive(:execute)
          .and_raise(::Gitlab::Auth::Identity::TooManyIdentitiesLinkedError)
      end
    end

    it 'drops the workflow and re-raises' do
      expect { service.execute }.to raise_error(::Gitlab::Auth::Identity::TooManyIdentitiesLinkedError)

      expect(Ai::DuoWorkflows::Workflow.last.status_name).to eq(:failed)
    end
  end

  context 'when the foundational flow declares an on_session_created hook' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }
    let(:registered_flow) { ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1 }
    let(:hook_calls) { [] }

    before do
      allow(registered_flow).to receive_messages(
        on_session_created: ->(resource:) { hook_calls << resource },
        resolve_noteable_for: merge_request
      )
    end

    it 'runs the hook for the resource the flow resolved' do
      expect(result).to be_success
      expect(hook_calls).to match_array([merge_request])
    end
  end

  context 'with a configured foundational flow' do
    include_examples 'success'

    it 'binds the workflow token to the resolved foundational flow', :aggregate_failures do
      resolved_params = { flow_config_id: 'developer', flow_config_schema_version: 'v1', flow_version: '^3.0.0' }
      minted_with = nil

      expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
        .with(workflow_definition.foundational_flow_reference, project, user: current_user, additional_context: nil)
        .once
        .and_return(resolved_params)
      expect_next_instance_of(::Ai::DuoWorkflows::WorkflowContextGenerationService) do |service|
        expect(service).to receive(:generate_workflow_token) do |**kwargs|
          minted_with = kwargs
          workflow_service_token_result
        end
      end
      expect(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new)
        .with(workflow: anything, params: hash_including(resolved_params))
        .and_call_original

      result

      expect(minted_with).to eq(
        flow_config_id: 'developer', flow_version: '^3.0.0', flow_config_schema_version: 'v1', flow_config: nil,
        workflow_id: Ai::DuoWorkflows::Workflow.last.id
      )
    end

    context 'with additional context' do
      let(:service) do
        described_class.new(
          container: project,
          current_user: current_user,
          goal: goal,
          source_branch: source_branch,
          workflow_definition: workflow_definition,
          additional_context: additional_context
        )
      end

      let(:additional_context) { [{ 'Category' => 'code_review_context', 'Content' => '{"depth":"standard"}' }] }

      it 'resolves the flow version with it' do
        expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
          .with(workflow_definition.foundational_flow_reference, project, user: current_user,
            additional_context: additional_context)
          .and_return({ flow_config_id: 'developer', flow_config_schema_version: 'v1', flow_version: '^3.0.0' })

        expect(result).to be_success
      end
    end

    context 'with a code review depth in the additional context' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let_it_be(:code_review_item) do
        create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'code_review/v1',
          project: project)
      end

      let_it_be(:code_review_enabled_flow) do
        create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: code_review_item)
      end

      let(:workflow_definition) { ::Ai::Catalog::FoundationalFlow.code_review_v1 }
      let(:goal) { merge_request.iid.to_s }
      let(:additional_context) do
        [{ 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(depth: depth) }]
      end

      let(:service) do
        described_class.new(
          container: project,
          current_user: current_user,
          goal: goal,
          source_branch: source_branch,
          workflow_definition: workflow_definition,
          additional_context: additional_context
        )
      end

      before do
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_call_original
        stub_feature_flags(duo_code_review_deep_flow: true, duo_code_review_standard_structured_findings: true)
      end

      where(:depth, :flow_id, :flow_version) do
        [
          ['standard', 'code_review', '^4.0.0'],
          ['deep', 'deep_code_review', '1.0.0']
        ]
      end

      with_them do
        it 'records the flow version the depth picks' do
          expect(result).to be_success

          expect(::Gitlab::Json::SafeParser.parse(result.payload[:workflow].flow_metadata_json)).to eq(
            'flow_id' => flow_id, 'schema_version' => 'v1', 'flow_version' => flow_version,
            'flow_version_constraint' => flow_version
          )
        end
      end
    end

    it 'creates the workflow with the resolved service_account' do
      expect(result).to be_success

      workflow = result.payload[:workflow]
      expect(workflow.service_account).to eq(group_level_service_account)
      expect(workflow.service_account_id).to eq(group_level_service_account.id)
    end

    it 'links the workflow to the latest released version of the catalog item' do
      item = Ai::Catalog::Item.find(catalog_item.id)
      released_version = create(:ai_catalog_flow_version, :released, item: item)

      expect(result).to be_success
      expect(result.payload[:workflow].ai_catalog_item_version).to eq(released_version)
    end

    it 'passes the root namespace to metadata for extended logging check' do
      expect(::Gitlab::DuoWorkflow::Client).to receive(:metadata)
        .with(current_user, namespace: project.root_ancestor, project: project)
        .and_call_original

      result
    end

    context 'when workflow_definition has no report_artifacts' do
      it 'forwards nil report_artifacts to StartWorkflowService' do
        expect(Ai::DuoWorkflows::StartWorkflowService).to receive(:new)
          .with(workflow: anything, params: hash_including(
            report_artifacts: nil
          ))
          .and_call_original

        result
      end
    end
  end
end
