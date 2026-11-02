# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ConnectionConfigService, feature_category: :duo_agent_platform do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, organizations: [organization]) }
  let_it_be(:root_namespace) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_namespace) }
  let_it_be(:foreign_namespace) { create(:group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }

  let(:gitlab_token) { 'gitlab-oauth-token' }
  let(:namespace) { root_namespace }
  let(:passed_project) { nil }
  let(:passed_workflow) { workflow }
  let(:server_capabilities) { ['some_capability'] }
  let(:forwarded_grpc_metadata) { {} }
  let(:client_type) { nil }
  let(:feature_setting) { nil }
  let(:should_bill) { false }
  let(:model_metadata_from_service) { {} }
  let(:cloud_connector_headers) do
    { 'authorization' => 'Bearer cc-token', 'x-gitlab-authentication-type' => 'oidc' }
  end

  # Captured so the tool access policies, which are only observable through the
  # cloud connector token claims, can be asserted on.
  let(:captured_cloud_connector_args) { {} }

  let(:mcp_config_service) do
    instance_double(
      Ai::DuoWorkflows::McpConfigService,
      execute: { gitlab: { URL: 'http://mcp.example.com' } },
      gitlab_enabled_tools: %w[get_issue list_issues],
      preapproved_tool_names: []
    )
  end

  let(:request_metadata) do
    described_class::RequestMetadata.new(
      project_id: '11',
      namespace_id: '22',
      client_type: client_type,
      organization_id: organization.id,
      feature_setting_name: :duo_agent_platform,
      user_selected_model_identifier: nil,
      workflow_definition: 'chat',
      environment: nil,
      ai_catalog_item_version_id: nil,
      forwarded_grpc_metadata: forwarded_grpc_metadata,
      trusted_job_caller: false
    )
  end

  let(:service) do
    described_class.new(
      user,
      gitlab_token,
      root_namespace: root_namespace,
      namespace: namespace,
      request_metadata: request_metadata,
      server_capabilities: server_capabilities,
      workflow: passed_workflow,
      project: passed_project
    )
  end

  subject(:config) { service.execute }

  before do
    allow(Gitlab::DuoWorkflow::Client).to receive(:cloud_connector_headers) do |**args|
      captured_cloud_connector_args.replace(args)
      cloud_connector_headers
    end
    allow(Gitlab::DuoWorkflow::Client).to receive_messages(
      url_for: 'dws.example.com:443',
      secure?: true,
      enable_extended_logging?: false
    )

    allow(Ai::FeatureSettingSelectionService).to receive(:new).and_return(
      instance_double(
        Ai::FeatureSettingSelectionService,
        execute: ServiceResponse.success(payload: feature_setting)
      )
    )
    allow(Ai::DuoWorkflows::McpConfigService).to receive(:new).and_return(mcp_config_service)
    allow(Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).to receive(:new).and_return(
      instance_double(
        Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService,
        execute: model_metadata_from_service
      )
    )
    allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).and_return(should_bill)
  end

  describe '#execute' do
    it 'returns the payload Workhorse expects' do
      expect(config).to include(
        Service: {
          Headers: a_hash_including('x-gitlab-unidirectional-streaming' => 'enabled'),
          URI: 'dws.example.com:443',
          Secure: true
        },
        GitlabToken: gitlab_token,
        McpServers: { gitlab: { URL: 'http://mcp.example.com' } },
        LockConcurrentFlow: true,
        ServerCapabilities: ['some_capability']
      )
    end

    it 'resolves the DWS endpoint from the feature setting' do
      config

      expect(Gitlab::DuoWorkflow::Client).to have_received(:url_for)
        .with(feature_setting: feature_setting, user: user)
      expect(Gitlab::DuoWorkflow::Client).to have_received(:secure?).with(feature_setting: feature_setting)
    end

    describe 'TimeoutHTTPRequests' do
      it 'follows the feature flag' do
        stub_feature_flags(timeout_dap_http_requests_in_workhorse: false)

        expect(config[:TimeoutHTTPRequests]).to be(false)
      end
    end

    describe 'RejectInvalidClientEvents' do
      it 'is true when the feature flag is enabled' do
        stub_feature_flags(duo_workflow_reject_invalid_client_events: user)

        expect(config[:RejectInvalidClientEvents]).to be(true)
      end

      it 'is false when the feature flag is disabled' do
        stub_feature_flags(duo_workflow_reject_invalid_client_events: false)

        expect(config[:RejectInvalidClientEvents]).to be(false)
      end
    end

    describe 'MaxConcurrentActions' do
      it 'allows concurrent actions when the feature flag is enabled' do
        stub_feature_flags(duo_workflow_concurrent_actions_in_workhorse: user)

        expect(config[:MaxConcurrentActions]).to eq(described_class::MAX_CONCURRENT_ACTIONS)
      end

      it 'runs actions one at a time when the feature flag is disabled' do
        stub_feature_flags(duo_workflow_concurrent_actions_in_workhorse: false)

        expect(config[:MaxConcurrentActions]).to eq(1)
      end
    end
  end

  describe 'gRPC headers' do
    subject(:grpc_headers) { config.dig(:Service, :Headers) }

    it 'builds on the cloud connector headers' do
      expect(grpc_headers).to include(
        'authorization' => 'Bearer cc-token',
        'x-gitlab-authentication-type' => 'oidc',
        'x-gitlab-unidirectional-streaming' => 'enabled',
        'x-gitlab-enabled-mcp-server-tools' => 'get_issue,list_issues',
        'x-gitlab-self-hosted-dap-billing-enabled' => 'false',
        'x-gitlab-extended-logging' => 'false'
      )
    end

    it 'does not send the GitLab token to DWS' do
      expect(grpc_headers).not_to have_key('x-gitlab-oauth-token')
    end

    context 'when duo_workflow_omit_gitlab_token_from_dws_metadata is disabled' do
      before do
        stub_feature_flags(duo_workflow_omit_gitlab_token_from_dws_metadata: false)
      end

      it 'sends the GitLab token to DWS' do
        expect(grpc_headers).to include('x-gitlab-oauth-token' => gitlab_token)
      end

      it 'still returns the GitLab token to Workhorse' do
        expect(config[:GitlabToken]).to eq(gitlab_token)
      end
    end

    it 'adds the organization header' do
      expect(grpc_headers).to include('x-gitlab-organization-id' => organization.id.to_s)
    end

    it 'attributes usage to the workflow service account when there is one' do
      grpc_headers

      expect(Gitlab::DuoWorkflow::Client).to have_received(:cloud_connector_headers)
        .with(hash_including(
          user: user,
          project_id: '11',
          namespace_id: 22,
          governing_namespace_id: root_namespace.id,
          subject: workflow.service_account || user
        ))
    end

    context 'when there is no workflow' do
      let(:passed_workflow) { nil }

      it 'attributes usage to the current user' do
        grpc_headers

        expect(Gitlab::DuoWorkflow::Client).to have_received(:cloud_connector_headers)
          .with(hash_including(subject: user))
      end
    end

    describe 'trusted flow id claim' do
      let(:request_metadata) { super().with(trusted_job_caller: true) }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'is not sent for a flow without gitlab_hosted_runner_only' do
        grpc_headers

        expect(captured_cloud_connector_args[:flow_config_id]).to be_nil
      end

      context 'when the workflow runs a gitlab_hosted_runner_only flow' do
        let_it_be(:bl_workflow) do
          create(:duo_workflows_workflow, user: user, project: project,
            workflow_definition: 'bl_security/experimental')
        end

        let(:passed_workflow) { bl_workflow }

        it 'sends the flow config id to the workflow\'s own job' do
          grpc_headers

          expect(captured_cloud_connector_args[:flow_config_id]).to eq('bl_security')
        end

        context 'when the client reported another flow' do
          let(:passed_workflow) do
            create(:duo_workflows_workflow, user: user, project: project,
              workflow_definition: 'bl_security/experimental',
              flow_metadata_json: { flow_id: 'other_flow', schema_version: 'experimental',
                                    flow_version: '1.0.0' }.to_json)
          end

          it 'sends the flow the definition resolves to' do
            grpc_headers

            expect(captured_cloud_connector_args[:flow_config_id]).to eq('bl_security')
          end
        end

        context 'when the caller is not the workflow\'s own job' do
          let(:request_metadata) { super().with(trusted_job_caller: false) }

          it 'is not sent' do
            grpc_headers

            expect(captured_cloud_connector_args[:flow_config_id]).to be_nil
          end
        end

        context 'when the flow is blocked by its feature flag' do
          before do
            stub_feature_flags(bl_security_analyzer: false)
          end

          it 'is not sent' do
            grpc_headers

            expect(captured_cloud_connector_args[:flow_config_id]).to be_nil
          end
        end
      end

      context 'when there is no workflow' do
        let(:passed_workflow) { nil }

        it 'is not sent' do
          grpc_headers

          expect(captured_cloud_connector_args[:flow_config_id]).to be_nil
        end
      end
    end

    describe 'client type' do
      context 'when sent as a param' do
        let(:client_type) { 'browser' }

        it 'is used' do
          expect(grpc_headers).to include('x-gitlab-client-type' => 'browser')
        end
      end

      context 'when sent as both a param and a header' do
        let(:client_type) { 'browser' }
        let(:forwarded_grpc_metadata) { { 'x-gitlab-client-type' => 'vscode' } }

        it 'prefers the forwarded header' do
          expect(grpc_headers).to include('x-gitlab-client-type' => 'vscode')
        end
      end

      context 'when neither is sent' do
        it 'falls back to the identity resolved for the request' do
          Gitlab::ApplicationContext.with_context(client_type: 'mobile', client_name: 'gitlab-mobile-ios') do
            expect(grpc_headers).to include(
              'x-gitlab-client-type' => 'mobile',
              'x-gitlab-client-name' => 'gitlab-mobile-ios'
            )
          end
        end
      end
    end

    describe 'forwarded metadata' do
      let(:forwarded_grpc_metadata) { { 'x-gitlab-client-name' => 'gitlab-vscode-extension' } }

      it 'is merged in' do
        expect(grpc_headers).to include('x-gitlab-client-name' => 'gitlab-vscode-extension')
      end
    end

    describe 'model prompt cache' do
      it 'reads the namespace setting' do
        allow(namespace).to receive(:namespace_settings).and_return(
          instance_double(NamespaceSetting, model_prompt_cache_enabled: true)
        )

        expect(grpc_headers).to include('x-gitlab-model-prompt-cache-enabled' => 'true')
      end

      context 'when the namespace has no settings' do
        it 'falls back to the root namespace' do
          allow(namespace).to receive(:namespace_settings).and_return(nil)
          allow(root_namespace).to receive(:model_prompt_cache_enabled).and_return(true)

          expect(grpc_headers).to include('x-gitlab-model-prompt-cache-enabled' => 'true')
        end
      end
    end

    describe 'model metadata' do
      let(:model_metadata_from_service) { { 'x-gitlab-model-metadata' => 'from-service' } }

      it 'uses the resolved model metadata' do
        expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
      end

      context 'when the workflow stored the model it resolved to' do
        let(:stored_metadata) { '{"provider":"gitlab","name":"claude_sonnet_4_5_vertex"}' }
        let(:parser) do
          instance_double(
            Gitlab::Ai::ModelSelection::ModelDefinitionResponseParser,
            default_model_refs_for_feature: %w[claude_sonnet_4_5 claude_sonnet_4_5_vertex]
          )
        end

        before do
          allow(workflow).to receive(:model_metadata_json).and_return(stored_metadata)
          allow(Ai::ModelSelection::ModelDefinitions).to receive(:fetch).and_return(
            instance_double(Ai::ModelSelection::ModelDefinitions, parser: parser)
          )
        end

        it 'replays the stored metadata instead of re-resolving' do
          expect(grpc_headers).to include(
            Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY => stored_metadata
          )
          expect(Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).not_to have_received(:new)
        end

        context 'when the user selected a model' do
          let(:request_metadata) { super().with(user_selected_model_identifier: 'fable_5_1') }

          it 're-resolves from the user selection' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
            expect(grpc_headers)
              .not_to include(Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY)

            expect(Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService).to have_received(:new)
              .with(hash_including(user_selected_model_identifier: 'fable_5_1'))
          end
        end

        context 'when the stored model is no longer one the default balances across' do
          let(:stored_metadata) { '{"provider":"gitlab","name":"fable_5_1"}' }

          it 're-resolves so switching back to the default takes effect' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
            expect(grpc_headers)
              .not_to include(Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY)
          end
        end

        context 'when the stored metadata does not name a model' do
          let(:stored_metadata) { '{"provider":"gitlab"}' }

          it 're-resolves' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
          end
        end

        context 'when the stored metadata is malformed' do
          let(:stored_metadata) { 'not json' }

          it 're-resolves' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
          end
        end

        context 'when the stored metadata is not a JSON object' do
          let(:stored_metadata) { '["claude_sonnet_4_5_vertex"]' }

          it 're-resolves' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
          end
        end

        context 'when the model definitions are unavailable' do
          let(:parser) { nil }

          it 're-resolves' do
            expect(grpc_headers).to include('x-gitlab-model-metadata' => 'from-service')
          end
        end
      end
    end
  end

  describe 'CloudServiceForSelfHosted' do
    it 'is absent when the instance is not billed for self-hosted DAP' do
      expect(config[:CloudServiceForSelfHosted]).to be_nil
    end

    context 'when the instance is billed for self-hosted DAP' do
      let(:should_bill) { true }

      before do
        allow(CloudConnector::Tokens).to receive(:cloud_connector_token).and_return('self-hosted-token')
        allow(Gitlab::DuoWorkflow::Client).to receive(:cloud_connected_url).and_return('cloud.example.com:443')
      end

      it 'points at the cloud service with a cloud connector token' do
        expect(config[:CloudServiceForSelfHosted]).to match(
          Headers: a_hash_including('authorization' => 'Bearer self-hosted-token'),
          URI: 'cloud.example.com:443',
          Secure: true
        )
      end

      it 'leaves the gRPC authorization header untouched' do
        expect(config.dig(:Service, :Headers)).to include('authorization' => 'Bearer cc-token')
      end
    end
  end

  describe 'MCP enforcement namespace' do
    context 'when a project is in scope' do
      let(:passed_project) { project }

      it 'enforces on the project namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: project.project_namespace))
      end
    end

    context 'when the namespace belongs to the validated root' do
      let(:namespace) { subgroup }

      it 'enforces on the most specific namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: subgroup))
      end
    end

    context 'when the namespace is outside the validated root' do
      let(:namespace) { foreign_namespace }

      it 'anchors enforcement to the root namespace' do
        config

        expect(Ai::DuoWorkflows::McpConfigService).to have_received(:new)
          .with(user, gitlab_token, hash_including(namespace: root_namespace))
      end
    end
  end

  describe 'tool access policies' do
    let(:no_policies) { { allow: [], ask: [], deny: [] } }

    # The `ws` handshake has no workflow until the client sends StartWorkflowRequest, so the
    # environment has to come off the request or the surface silently resolves as web.
    describe 'which environment reaches the surface resolver' do
      using RSpec::Parameterized::TableSyntax

      let(:request_metadata) { super().with(environment: 'ide') }

      before do
        allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: nil, ungoverned?: false)
        allow(Ai::ToolRules::ResolutionService).to receive(:new).and_return(
          instance_double(Ai::ToolRules::ResolutionService, execute: ServiceResponse.error(message: 'x'))
        )
      end

      # The last row is why this is not `||`: that would fall through to the request for a
      # workflow whose environment is nil, letting a caller pick the surface for a session
      # it named.
      where(:case_name, :names_a_workflow, :workflow_environment, :expected) do
        'when no workflow is named'               | false | nil  | 'ide'
        'when the named workflow carries one'     | true  | :web | 'web'
        'when the named workflow carries none'    | true  | nil  | nil
      end

      with_them do
        let(:passed_workflow) do
          next unless names_a_workflow

          build_stubbed(:duo_workflows_workflow, user: user, project: project, environment: workflow_environment)
        end

        it 'resolves the surface from that environment' do
          expect(Ai::ToolRules::GovernanceSurface).to receive(:for)
            .with(hash_including(environment: expected)).and_return(nil)

          config
        end
      end
    end

    def resolved_policies
      config

      captured_cloud_connector_args[:tool_access_policies]
    end

    context 'when governance resolves a verdict' do
      before do
        allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :web, ungoverned?: false)
        allow(Ai::ToolRules::ResolutionService).to receive(:new).and_return(
          instance_double(Ai::ToolRules::ResolutionService, execute: resolution_result)
        )
      end

      let(:resolution_result) do
        ServiceResponse.success(payload: {
          pre_approved_tools: %w[get_issue read_file],
          ask_tools: %w[read_file],
          denied_tools: %w[run_command]
        })
      end

      it 'subtracts ask and deny verdicts from the allow list' do
        expect(resolved_policies).to eq(
          allow: %w[get_issue],
          ask: %w[read_file],
          deny: %w[run_command],
          ceiling: true
        )
      end

      context 'when duo_workflow_governance_ceiling is disabled' do
        before do
          stub_feature_flags(duo_workflow_governance_ceiling: false)
        end

        it 'leaves the ceiling out of the claim' do
          expect(resolved_policies).not_to have_key(:ceiling)
        end
      end

      it 'hands the resolved deny list to the MCP tools header' do
        expect(mcp_config_service).to receive(:gitlab_enabled_tools).with(denied: %w[run_command]).and_return([])

        config
      end

      it 'hands the resolved deny list to the MCP server config' do
        expect(mcp_config_service).to receive(:execute).with(denied: %w[run_command]).and_return({})

        config
      end

      context 'when MCP contributes pre-approved tools' do
        let(:mcp_config_service) do
          instance_double(
            Ai::DuoWorkflows::McpConfigService,
            execute: {},
            gitlab_enabled_tools: [],
            preapproved_tool_names: %w[gitlab_search read_file]
          )
        end

        it 'appends them but still honours the ask verdict' do
          expect(resolved_policies).to eq(
            allow: %w[get_issue gitlab_search],
            ask: %w[read_file],
            deny: %w[run_command],
            ceiling: true
          )
        end
      end

      it 'stays empty when the surface is ungoverned' do
        allow(Ai::ToolRules::GovernanceSurface).to receive(:ungoverned?).and_return(true)

        expect(resolved_policies).to eq(no_policies)
      end

      context 'when resolution fails' do
        let(:resolution_result) { ServiceResponse.error(message: 'nope') }

        it 'stays empty' do
          expect(resolved_policies).to eq(no_policies)
        end
      end
    end
  end

  describe 'resolving governance from the executed workflow' do
    let_it_be(:foreign_project) { create(:project, group: foreign_namespace) }
    let_it_be(:foreign_workflow) { create(:duo_workflows_workflow, user: user, project: foreign_project) }
    let_it_be(:namespace_workflow) do
      create(:duo_workflows_workflow, user: user, project: nil, namespace: root_namespace)
    end

    def stub_resolution
      instance_double(
        Ai::ToolRules::ResolutionService,
        execute: ServiceResponse.success(
          payload: { pre_approved_tools: [], ask_tools: [], denied_tools: [] }
        )
      )
    end

    before do
      allow(Ai::ToolRules::GovernanceSurface).to receive_messages(for: :web, ungoverned?: false)
    end

    context 'when the workflow runs outside the requested namespace' do
      let(:passed_workflow) { foreign_workflow }

      it "resolves from the workflow's own container, not the request" do
        expect(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(hash_including(namespace: foreign_namespace, project: foreign_project))
          .and_return(stub_resolution)

        config
      end
    end

    context 'when the workflow is scoped to a namespace rather than a project' do
      let(:passed_workflow) { namespace_workflow }

      it 'resolves from that namespace with no project' do
        expect(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(hash_including(namespace: root_namespace, project: nil))
          .and_return(stub_resolution)

        config
      end
    end

    context 'when no workflow is given' do
      let(:passed_workflow) { nil }
      let(:passed_project) { project }

      it 'falls back to the request context, as before' do
        expect(Ai::ToolRules::ResolutionService).to receive(:new)
          .with(hash_including(namespace: root_namespace, project: project))
          .and_return(stub_resolution)

        config
      end

      it 'mints a token with no workflow_id claim' do
        allow(Ai::ToolRules::ResolutionService).to receive(:new).and_return(stub_resolution)

        config

        expect(captured_cloud_connector_args[:workflow_id]).to be_nil
      end
    end

    it 'lets a requested project the workflow does not run in tighten, by re-resolving for it' do
      sibling = create(:project, group: subgroup)
      allow(service).to receive(:project).and_return(sibling)

      expect(Ai::ToolRules::ResolutionService).to receive(:new)
        .with(hash_including(project: project)).and_return(stub_resolution)
      expect(Ai::ToolRules::ResolutionService).to receive(:new)
        .with(hash_including(project: sibling)).and_return(stub_resolution)

      config
    end

    it 'binds the minted token to the workflow' do
      allow(Ai::ToolRules::ResolutionService).to receive(:new).and_return(stub_resolution)

      config

      expect(captured_cloud_connector_args[:workflow_id]).to eq(workflow.id)
    end
  end
end
