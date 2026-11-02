# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Helpers::DuoWorkflowHelpers, feature_category: :duo_agent_platform do
  let(:helper) do
    Class.new do
      include API::Helpers::DuoWorkflowHelpers
      include Gitlab::Utils::StrongMemoize

      attr_accessor :params

      def current_user
        nil
      end
    end.new
  end

  let(:raising_helper) do
    Class.new do
      include API::Helpers::DuoWorkflowHelpers

      attr_accessor :current_user

      def forbidden!(message)
        raise message
      end
    end.new
  end

  describe '#start_workflow_params' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }
    let_it_be(:service_account) { create(:user, :ai_service_account) }

    let(:workflow_context_service) do
      instance_double(
        ::Ai::DuoWorkflows::WorkflowContextGenerationService,
        generate_oauth_token_with_composite_identity_support: ServiceResponse.success(
          payload: { oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token') }
        ),
        duo_agent_platform_feature_setting: nil
      )
    end

    before do
      helper.params = { workflow_definition: workflow_definition }
      allow(helper).to receive_messages(
        current_user: user,
        workflow_context_generation_service: workflow_context_service,
        find_request_namespace: nil,
        find_project: project,
        headers: {}
      )
      allow(Gitlab::DuoWorkflow::Client).to receive(:metadata).and_return({})
    end

    context 'with a foundational flow' do
      let(:workflow_definition) { 'developer/v1' }
      let(:resolved_params) do
        { flow_config_id: 'developer', flow_config_schema_version: 'v1', flow_version: '^3.0.0' }
      end

      it 'uses the resolved flow ID, version, and schema version for both the token and start parameters' do
        expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
          .with(workflow_definition, project, user: user)
          .once
          .and_return(resolved_params)
        expect(workflow_context_service).to receive(:generate_workflow_token)
          .with(flow_config_id: 'developer', flow_version: '^3.0.0', flow_config_schema_version: 'v1', workflow_id: 1)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        expect(helper.start_workflow_params(1, container: project, service_account: service_account))
          .to include(resolved_params)
      end

      it 'uses an explicitly authorized canonical definition instead of the request value' do
        helper.params = { workflow_definition: 'Developer' }

        expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
          .with(workflow_definition, project, user: user)
          .once
          .and_return(resolved_params)
        expect(workflow_context_service).to receive(:generate_workflow_token)
          .with(flow_config_id: 'developer', flow_version: '^3.0.0', flow_config_schema_version: 'v1', workflow_id: 1)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        expect(helper.start_workflow_params(1, container: project, service_account: service_account,
          workflow_definition: workflow_definition)).to include(resolved_params)
      end
    end

    describe 'source_branch' do
      let(:workflow_definition) { 'fix_pipeline/v1' }
      let(:definition) { ::Ai::Catalog::FoundationalFlow.fix_pipeline_v1 }

      subject(:source_branch) do
        helper.start_workflow_params(1, container: project, service_account: service_account)[:source_branch]
      end

      before do
        helper.params = { workflow_definition: workflow_definition, goal: '42' }
        allow(workflow_context_service).to receive(:generate_workflow_token)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))
      end

      it 'falls back to the branch the flow resolves from the goal' do
        allow(definition).to receive(:resolve_source_branch_for)
          .with(project: project, goal: '42').and_return('resolved-branch')

        expect(source_branch).to eq('resolved-branch')
      end

      it 'uses the source branch the caller names' do
        helper.params[:source_branch] = 'explicit-branch'

        expect(definition).not_to receive(:resolve_source_branch_for)
        expect(source_branch).to eq('explicit-branch')
      end
    end

    context 'with a legacy flow' do
      let(:workflow_definition) { 'software_development' }

      it 'leaves the flow config unbound but still binds the token to the workflow' do
        expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call)
          .with(workflow_definition, project, user: user)
          .once
          .and_return({})
        expect(workflow_context_service).to receive(:generate_workflow_token)
          .with(flow_config_id: nil, flow_version: nil, flow_config_schema_version: nil, workflow_id: 1)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        expect(helper.start_workflow_params(1, container: project, service_account: service_account))
          .not_to have_key(:flow_config_id)
      end

      it 'does not declare report artifacts' do
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})
        allow(workflow_context_service).to receive(:generate_workflow_token)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        expect(helper.start_workflow_params(1, container: project, service_account: service_account))
          .not_to have_key(:report_artifacts)
      end
    end

    context 'with a foundational flow that declares report artifacts' do
      let(:workflow_definition) { 'bl_security/experimental' }
      let(:report_artifacts) { ::Ai::Catalog::FoundationalFlow.bl_security_experimental.report_artifacts }

      it 'forwards the report artifacts so the reports are collected' do
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})
        allow(workflow_context_service).to receive(:generate_workflow_token)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        expect(report_artifacts).to be_present
        expect(helper.start_workflow_params(1, container: project, service_account: service_account))
          .to include(report_artifacts: report_artifacts)
      end
    end
  end

  describe '#validate_flow_start_request!' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project) }

    let(:goal_helper) do
      Class.new do
        include API::Helpers::DuoWorkflowHelpers

        attr_accessor :params, :current_user

        def bad_request!(message)
          raise ArgumentError, message
        end
      end.new
    end

    let(:container) { project }
    let(:definition) { ::Ai::Catalog::FoundationalFlow.code_review_v1 }
    let(:goal_result) { ServiceResponse.error(message: 'Merge request not found', reason: :invalid_goal) }
    let(:can_read_merge_request) { true }

    subject(:validate) { goal_helper.validate_flow_start_request!('code_review/v1', container, client_executed: true) }

    before do
      goal_helper.params = { goal: '42' }
      goal_helper.current_user = user
      allow(definition).to receive(:validate_start_request)
        .with(container: container, goal: '42', additional_context: nil, client_executed: true)
        .and_return(goal_result)
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_merge_request, project)
        .and_return(can_read_merge_request)
    end

    context 'when the user can read merge requests' do
      it 'returns the validator message' do
        expect { validate }.to raise_error(ArgumentError, 'Merge request not found')
      end
    end

    context 'when the user cannot read merge requests' do
      let(:can_read_merge_request) { false }

      it 'returns a generic message' do
        expect { validate }.to raise_error(ArgumentError, 'Invalid goal')
      end
    end

    context 'when the container is not a project' do
      let_it_be(:group) { create(:group) }
      let(:container) { group }
      let(:goal_result) { ServiceResponse.error(message: 'Code reviews require a project context') }

      it 'returns the validator message' do
        expect { validate }.to raise_error(ArgumentError, 'Code reviews require a project context')
      end
    end

    context 'when the goal is valid' do
      let(:goal_result) { ServiceResponse.success(payload: { goal: '7' }) }

      it 'stores the normalized goal' do
        validate

        expect(goal_helper.params[:goal]).to eq('7')
      end
    end
  end

  describe '#verify_flow_composite_identity!' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:project) { create(:project, organization: organization) }
    let_it_be(:human) { create(:user) }
    let_it_be(:service_account) { create(:user, :service_account, organization: organization) }
    let_it_be(:other_service_account) { create(:user, :service_account, organization: organization) }

    let(:flow) { ::Ai::Catalog::FoundationalFlow.code_review_v1 }
    let(:composite_identity_actor) { service_account }
    let(:resolved) { ServiceResponse.success(payload: { service_account: service_account }) }

    let(:helper) { raising_helper }

    subject(:verify) { helper.verify_flow_composite_identity!(flow, project) }

    before do
      helper.current_user = human

      allow(::Gitlab::Auth::Identity)
        .to receive(:resolve_composite_identity_actor).with(human).and_return(composite_identity_actor)

      allow_next_instance_of(::Ai::Catalog::ItemConsumers::ResolveServiceAccountService) do |service|
        allow(service).to receive(:execute).and_return(resolved)
      end
    end

    it 'passes when the composite identity actor is the flow\'s resolved service account' do
      expect { verify }.not_to raise_error
    end

    shared_examples 'a forbidden request' do
      it 'is forbidden' do
        expect { verify }.to raise_error('This endpoint can only be accessed by Duo Workflow Service')
      end
    end

    context 'when the request carries no composite identity' do
      let(:composite_identity_actor) { nil }

      it_behaves_like 'a forbidden request'
    end

    context 'when the composite identity actor is not a service account' do
      let(:composite_identity_actor) { human }

      it_behaves_like 'a forbidden request'
    end

    context 'when the service account cannot be resolved for the container' do
      let(:resolved) { ServiceResponse.error(message: 'No service account') }

      it_behaves_like 'a forbidden request'
    end

    context 'when a different service account is resolved for the container' do
      let(:resolved) { ServiceResponse.success(payload: { service_account: other_service_account }) }

      it_behaves_like 'a forbidden request'
    end
  end

  describe '#validate_start_workflow_service_account!' do
    let(:composite_service_account) { build_stubbed(:user, :ai_service_account) }
    let(:plain_service_account) { build_stubbed(:user, :service_account) }
    let(:human) { build_stubbed(:user) }

    let(:helper) { raising_helper }

    subject(:validate) { helper.validate_start_workflow_service_account!(service_account) }

    context 'with a composite identity service account' do
      let(:service_account) { composite_service_account }

      it 'returns it, so the caller starts the workflow with it' do
        expect(validate).to eq(composite_service_account)
      end
    end

    shared_examples 'refuses to start the workflow' do
      it 'is forbidden, naming what is missing' do
        expect { validate }.to raise_error(described_class::COMPOSITE_IDENTITY_SERVICE_ACCOUNT_MESSAGE)
      end
    end

    context 'with a service account that does not enforce composite identity' do
      let(:service_account) { plain_service_account }

      it_behaves_like 'refuses to start the workflow'
    end

    context 'with a user who is not a service account' do
      let(:service_account) { human }

      it_behaves_like 'refuses to start the workflow'
    end

    context 'with no service account at all' do
      let(:service_account) { nil }

      it_behaves_like 'refuses to start the workflow'
    end
  end

  describe '#link_vulnerability_to_user_triggered_workflow' do
    let_it_be(:project) { create(:project) }
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: project,
        workflow_definition: 'resolve_sast_vulnerability/v1')
    end

    before do
      helper.params = { goal: vulnerability.id.to_s }
    end

    it 'creates a Vulnerabilities::TriggeredWorkflow row linking the vulnerability and workflow' do
      expect { helper.link_vulnerability_to_user_triggered_workflow(workflow) }
        .to change { ::Vulnerabilities::TriggeredWorkflow.count }.by(1)

      record = ::Vulnerabilities::TriggeredWorkflow.last
      expect(record.workflow_id).to eq(workflow.id)
      expect(record.vulnerability_occurrence_id).to eq(vulnerability.finding.id)
      expect(record.workflow_name).to eq('resolve_sast_vulnerability')
    end

    context 'when the workflow_definition is not one of the vulnerability definitions' do
      let(:other_workflow) { create(:duo_workflows_workflow, workflow_definition: 'software_developer') }

      it 'is a no-op' do
        expect { helper.link_vulnerability_to_user_triggered_workflow(other_workflow) }
          .not_to change { ::Vulnerabilities::TriggeredWorkflow.count }
      end
    end

    context 'when the workflow is nil' do
      it 'returns without creating a row' do
        expect { helper.link_vulnerability_to_user_triggered_workflow(nil) }
          .not_to change { ::Vulnerabilities::TriggeredWorkflow.count }
      end
    end

    context 'when the goal does not resolve to a vulnerability' do
      before do
        helper.params = { goal: '999999' }
      end

      it 'is a no-op' do
        expect { helper.link_vulnerability_to_user_triggered_workflow(workflow) }
          .not_to change { ::Vulnerabilities::TriggeredWorkflow.count }
      end
    end

    context 'when the resulting row is invalid' do
      it 'rescues the error, tracks it, and returns nil' do
        invalid_workflow = create(:duo_workflows_workflow,
          workflow_definition: 'resolve_sast_vulnerability/v1',
          project: create(:project))

        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(ActiveRecord::RecordInvalid),
          hash_including(workflow_id: invalid_workflow.id)
        )

        expect(helper.link_vulnerability_to_user_triggered_workflow(invalid_workflow)).to be_nil
      end
    end
  end

  describe '#inject_secret_fp_detection_context' do
    let(:user) { build_stubbed(:user) }
    let(:finding) { instance_double(Vulnerabilities::Finding, token_value: 'glpat-secret-token', secret_redacted?: false) }
    let(:vulnerability) { instance_double(Vulnerability, finding: finding) }

    before do
      allow(helper).to receive_messages(current_user: user, vulnerability_from_goal: vulnerability)
      allow(Ability).to receive(:allowed?).with(user, :read_vulnerability, vulnerability).and_return(true)
    end

    it 'appends both legacy and typed envelopes with the secret value', :aggregate_failures do
      expected_content = { "secret_value" => 'glpat-secret-token' }.to_json
      result = helper.inject_secret_fp_detection_context([])

      expect(result.map { |e| e["Category"] }).to contain_exactly(
        'secret_detection_context',
        'agent_platform_secrets_fp_detection_context'
      )
      result.each do |envelope|
        expect(envelope["Content"]).to eq(expected_content)
      end
    end

    context 'when the user cannot read the vulnerability' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :read_vulnerability, vulnerability).and_return(false)
      end

      it 'returns the context unchanged' do
        expect(helper.inject_secret_fp_detection_context([])).to eq([])
      end
    end

    context 'when the finding secret is redacted' do
      let(:finding) { instance_double(Vulnerabilities::Finding, secret_redacted?: true) }

      it 'returns the context unchanged' do
        expect(helper.inject_secret_fp_detection_context([])).to eq([])
      end
    end
  end

  describe '#push_ai_gateway_headers', :request_store, :saas_gitlab_com_subscriptions do
    let(:user) { build_stubbed(:user) }
    let(:group) { build_stubbed(:group) }
    let(:governing_namespace) { group }
    let(:written_headers) { {} }

    before do
      stub_feature_flags(internal_ai_usage: group)
      allow(helper).to receive(:current_user).and_return(user)
      allow(user).to receive_messages(governing_namespace: governing_namespace, allowed_to_use: nil)
      allow(::CloudConnector).to receive(:ai_headers).and_return({})
      allow(helper).to receive(:header) { |name, value| written_headers[name] = value }
    end

    subject(:pushed_flags) do
      helper.push_ai_gateway_headers

      written_headers.fetch('x-gitlab-enabled-feature-flags').split(',')
    end

    it 'sends internal_ai_usage without building a Cloud Connector token' do
      expect(::CloudConnector::Tokens).not_to receive(:get)

      expect(pushed_flags).to include('internal_ai_usage')
    end

    context 'when the flag is disabled' do
      before do
        stub_feature_flags(internal_ai_usage: false)
      end

      it 'omits internal_ai_usage' do
        expect(pushed_flags).not_to include('internal_ai_usage')
      end
    end

    context 'when the governing namespace is outside the pilot' do
      let(:governing_namespace) { build_stubbed(:group) }

      it 'omits internal_ai_usage' do
        expect(pushed_flags).not_to include('internal_ai_usage')
      end
    end

    context 'when there is no governing namespace' do
      let(:governing_namespace) { nil }

      it 'omits internal_ai_usage' do
        expect(pushed_flags).not_to include('internal_ai_usage')
      end
    end
  end

  describe '#push_feature_flags' do
    let_it_be(:user) { create(:user) }

    before do
      allow(helper).to receive(:current_user).and_return(user)
      allow(Gitlab::AiGateway).to receive(:push_feature_flag)
    end

    it 'pushes duo_chat_clarification_question_tool feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:duo_chat_clarification_question_tool, user)
    end

    it 'pushes dap_parallel_subagents feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:dap_parallel_subagents, user)
    end

    it 'pushes dap_tool_image_input feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:dap_tool_image_input, user)
    end

    it 'pushes dap_openai_non_strict_tools feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:dap_openai_non_strict_tools, user)
    end

    it 'pushes duo_chat_tool_call_limits feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:duo_chat_tool_call_limits, user)
    end

    context 'with the Feature Preview/Experimental setting', :request_store do
      let(:root_namespace) { build_stubbed(:group) }

      it 'pushes dap_workspace_agents when the setting is enabled' do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)

        helper.push_feature_flags(root_namespace)

        expect(Gitlab::AiGateway.enabled_feature_flags).to include(:dap_workspace_agents)
      end

      it 'does not push dap_workspace_agents when the setting is disabled' do
        stub_application_setting(instance_level_ai_beta_features_enabled: false)

        helper.push_feature_flags(root_namespace)

        expect(Gitlab::AiGateway.enabled_feature_flags).not_to include(:dap_workspace_agents)
      end

      it 'does not push dap_workspace_agents without a root namespace' do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)

        helper.push_feature_flags

        expect(Gitlab::AiGateway.enabled_feature_flags).not_to include(:dap_workspace_agents)
      end

      context 'when the dap_workspace_agents feature flag is disabled' do
        before do
          stub_feature_flags(dap_workspace_agents: false)
        end

        it 'does not push dap_workspace_agents even when the setting is enabled' do
          stub_application_setting(instance_level_ai_beta_features_enabled: true)

          helper.push_feature_flags(root_namespace)

          expect(Gitlab::AiGateway.enabled_feature_flags).not_to include(:dap_workspace_agents)
        end
      end
    end

    it 'pushes ai_model_release feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:ai_model_release, user)
    end

    it 'pushes dap_for_each feature flag' do
      helper.push_feature_flags

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:dap_for_each, user)
    end

    it 'pushes dw_read_blobs_api for the root namespace so the gateway can gate the blob read path' do
      root_namespace = create(:group)

      helper.push_feature_flags(root_namespace)

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:dw_read_blobs_api, root_namespace)
    end

    it 'pushes the duo_workflow_read_incremental_checkpoints kill switch for the root namespace' do
      root_namespace = create(:group)

      helper.push_feature_flags(root_namespace)

      expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
        .with(:duo_workflow_read_incremental_checkpoints, root_namespace)
    end

    context 'with the duo_developer_model_routing experiment' do
      it 'pushes the flag for the duo_developer flow' do
        helper.push_feature_flags(feature_setting_name: :duo_developer)

        expect(Gitlab::AiGateway).to have_received(:push_feature_flag)
          .with(:duo_developer_model_routing, user)
      end

      it 'does not push the flag for another flow' do
        helper.push_feature_flags(feature_setting_name: :duo_agent_platform)

        expect(Gitlab::AiGateway).not_to have_received(:push_feature_flag)
          .with(:duo_developer_model_routing, user)
      end

      # Callers that push headers without resolving a feature setting name, such as
      # push_ai_gateway_headers, must not push the flag.
      it 'does not push the flag when no feature setting name is given' do
        helper.push_feature_flags

        expect(Gitlab::AiGateway).not_to have_received(:push_feature_flag)
          .with(:duo_developer_model_routing, user)
      end
    end
  end
end
