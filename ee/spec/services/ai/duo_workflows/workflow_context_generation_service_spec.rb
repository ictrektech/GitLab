# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowContextGenerationService, :aggregate_failures, feature_category: :workflow_catalog do
  let_it_be_with_refind(:user) { create(:user) }
  let_it_be(:container) { create(:project, namespace: create(:group)) }
  let(:workflow_definition) { 'software_development' }
  let_it_be_with_reload(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }
  let(:trigger_source) { nil }
  let(:service) do
    described_class.new(
      current_user: user,
      organization: container.organization,
      workflow_definition: workflow_definition,
      container: container,
      service_account: service_account,
      trigger_source: trigger_source
    )
  end

  describe '#generate_oauth_token' do
    let(:oauth_service) { instance_double(Ai::DuoWorkflows::CreateOauthAccessTokenService) }
    let(:oauth_token) { instance_double(OauthAccessToken) }

    before do
      allow(Ai::DuoWorkflows::CreateOauthAccessTokenService).to receive(:new).and_return(oauth_service)
    end

    context 'when token creation succeeds' do
      before do
        allow(oauth_service).to receive(:execute).and_return(
          ServiceResponse.success(payload: { oauth_access_token: oauth_token })
        )
      end

      it 'returns success with oauth access token' do
        result = service.generate_oauth_token

        expect(result).to be_success
        expect(result.payload[:oauth_access_token]).to eq(oauth_token)
      end
    end

    context 'when token creation fails' do
      before do
        allow(oauth_service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'Token creation failed')
        )
      end

      it 'returns error with message and http status' do
        result = service.generate_oauth_token

        expect(result).to be_error
        expect(result.message).to eq('Token creation failed')
      end
    end
  end

  describe '#generate_composite_oauth_token' do
    let(:composite_oauth_service) { instance_double(Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService) }
    let(:oauth_token) { instance_double(OauthAccessToken) }

    before do
      allow(Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService).to receive(:new)
                                                                           .and_return(composite_oauth_service)
    end

    context 'when token creation succeeds' do
      before do
        allow(composite_oauth_service).to receive(:execute).and_return(
          ServiceResponse.success(payload: { oauth_access_token: oauth_token })
        )
      end

      it 'returns success with oauth access token' do
        result = service.generate_composite_oauth_token

        expect(result).to be_success
        expect(result.payload[:oauth_access_token]).to eq(oauth_token)
      end

      context 'when passing service_account' do
        let(:service_account) { build(:user, :service_account) }

        let(:service) do
          described_class.new(
            current_user: user,
            organization: container.organization,
            workflow_definition: workflow_definition,
            service_account: service_account,
            container: container
          )
        end

        it 'passes the service_account to CreateCompositeOauthAccessTokenService' do
          expect(Ai::DuoWorkflows::CreateCompositeOauthAccessTokenService)
            .to receive(:new)
            .with(a_hash_including(service_account:))
            .and_return(composite_oauth_service)

          service.generate_composite_oauth_token
        end
      end
    end

    context 'when token creation fails' do
      before do
        allow(composite_oauth_service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'Composite token creation failed')
        )
      end

      it 'returns error with message' do
        result = service.generate_composite_oauth_token

        expect(result).to be_error
        expect(result.message).to eq('Composite token creation failed')
      end
    end
  end

  describe '#generate_workflow_token' do
    let(:workflow_client) { instance_double(Ai::DuoWorkflow::DuoWorkflowService::Client) }
    let(:token_data) { { token: 'workflow_token', expires_at: 1.hour.from_now } }

    before do
      allow(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_return(workflow_client)
    end

    context 'when token generation succeeds' do
      before do
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: token_data)
        )
      end

      it 'returns success with token data' do
        result = service.generate_workflow_token

        expect(result).to be_success
        expect(result.payload).to include(token_data)
      end

      it 'forwards the container to the client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(container: container)
        ).and_return(workflow_client)

        service.generate_workflow_token
      end

      # The seam the direct_access endpoint relies on: a mint with no workflow to anchor to
      # must not sign a policy resolved from a namespace the caller named.
      describe 'resolve_governance' do
        it 'resolves governance by default' do
          expect(::Ai::ToolRules::ResolutionService).to receive(:new).and_call_original

          service.generate_workflow_token
        end

        it 'sends an empty policy but keeps the container when false', :aggregate_failures do
          expect(::Ai::ToolRules::ResolutionService).not_to receive(:new)
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(
              container: container, pre_approved_tools: [], denied_tools: [], ask_tools: []
            )
          ).and_return(workflow_client)

          service.generate_workflow_token(resolve_governance: false)
        end
      end

      it 'forwards the authorized foundational flow ID, version, and schema version to the client' do
        expect(workflow_client).to receive(:generate_token).with(
          flow_config_id: 'developer', flow_version: '^3.0.0', flow_config_schema_version: 'v1', flow_config: nil,
          workflow_id: nil
        ).and_return(ServiceResponse.success(payload: token_data))

        service.generate_workflow_token(
          flow_config_id: 'developer', flow_version: '^3.0.0', flow_config_schema_version: 'v1'
        )
      end

      it 'forwards the authoritative flow config to the client' do
        flow_config = { 'version' => 'v1' }

        expect(workflow_client).to receive(:generate_token).with(
          flow_config_id: nil, flow_version: nil, flow_config_schema_version: nil, flow_config: flow_config,
          workflow_id: nil
        ).and_return(ServiceResponse.success(payload: token_data))

        service.generate_workflow_token(flow_config: flow_config)
      end

      it 'forwards the workflow id to the client' do
        expect(workflow_client).to receive(:generate_token).with(
          flow_config_id: nil, flow_version: nil, flow_config_schema_version: nil, flow_config: nil, workflow_id: 42
        ).and_return(ServiceResponse.success(payload: token_data))

        service.generate_workflow_token(workflow_id: 42)
      end
    end

    context 'when token generation fails' do
      before do
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.error(message: 'Workflow token generation failed')
        )
      end

      it 'returns error with message' do
        result = service.generate_workflow_token

        expect(result).to be_error
        expect(result.message).to eq('Workflow token generation failed')
      end
    end

    context 'for duo_workflow_service_url' do
      let(:cloud_connector_url) { 'cloud.staging.gitlab.com:443' }
      let(:self_hosted_url) { 'self-hosted-dap-service-url:50052' }
      let(:duo_agent_platform_feature_setting) { nil }

      before do
        allow(Gitlab::DuoWorkflow::Client).to receive_messages(self_hosted_url: self_hosted_url,
          cloud_connected_url: cloud_connector_url)
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: { token: 't', expires_at: 1.hour.from_now })
        )
      end

      shared_examples 'initializes client with expected service url' do
        it 'passes expected duo_workflow_service_url to client' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(
              duo_workflow_service_url: expected_service_server_url,
              current_user: user,
              secure: ::Gitlab::DuoWorkflow::Client.secure?(
                feature_setting: service.duo_agent_platform_feature_setting
              ),
              feature_setting: service.duo_agent_platform_feature_setting
            )
          ).and_return(workflow_client)

          result = service.generate_workflow_token

          expect(result).to be_success
        end
      end

      context 'when self-hosted feature setting exists' do
        let(:expected_service_server_url) { self_hosted_url }

        let_it_be(:model) do
          create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
        end

        let_it_be(:duo_agent_platform_feature_setting) do
          create(:ai_feature_setting, :duo_agent_platform, self_hosted_model: model)
        end

        it_behaves_like 'initializes client with expected service url'
      end

      context 'when instance level model selection exists' do
        let(:expected_service_server_url) { cloud_connector_url }

        let_it_be(:duo_agent_platform_feature_setting) do
          create(:instance_model_selection_feature_setting, feature: :duo_agent_platform)
        end

        it_behaves_like 'initializes client with expected service url'
      end

      context 'when namespace level model selection exists', :saas do
        let(:expected_service_server_url) { cloud_connector_url }

        let_it_be(:duo_agent_platform_feature_setting) do
          create(:ai_namespace_feature_setting,
            namespace: container.namespace,
            feature: :duo_agent_platform,
            offered_model_ref: 'claude_sonnet_3_7_20250219')
        end

        it_behaves_like 'initializes client with expected service url'
      end

      context 'when no feature setting exists' do
        let(:expected_service_server_url) { cloud_connector_url }

        it_behaves_like 'initializes client with expected service url'
      end
    end

    context 'when a flow resolves its own feature setting' do
      using RSpec::Parameterized::TableSyntax

      let(:cloud_connector_url) { 'cloud.staging.gitlab.com:443' }
      let(:self_hosted_url) { 'self-hosted-dap-service-url:50052' }
      let(:grpc_stub) { instance_double(DuoWorkflowService::DuoWorkflow::Stub) }

      let(:flow_feature) do
        {
          'code_review/v1' => :review_merge_request_dap,
          'developer/v1' => :duo_developer,
          'secrets_fp_detection/v1' => :secret_vulnerability_fp_detection
        }.fetch(workflow_definition)
      end

      let(:expected_url) { destination == :self_hosted ? self_hosted_url : cloud_connector_url }
      let(:expected_token) { destination == :self_hosted ? 'self-issued jwt' : 'synced jwt' }

      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      before do
        stub_feature_flags(duo_code_review_deep_flow: false)

        allow(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_call_original
        allow(Gitlab::DuoWorkflow::Client).to receive_messages(self_hosted_url: self_hosted_url,
          cloud_connected_url: cloud_connector_url)
        allow(DuoWorkflowService::DuoWorkflow::Stub).to receive(:new).and_return(grpc_stub)
        allow(grpc_stub).to receive(:generate_token)
          .and_return(DuoWorkflowService::GenerateTokenResponse.new(token: 'workflow jwt'))

        allow(CloudConnector::Tokens::TokenLoader).to receive(:new)
          .and_return(instance_double(CloudConnector::Tokens::TokenLoader, token: 'synced jwt'))
        allow(CloudConnector::CachingKeyLoader).to receive(:private_jwk)
          .and_return(build(:cloud_connector_keys).to_jwk)
        allow_next_instance_of(CloudConnector::Tokens::TokenIssuer) do |issuer|
          allow(issuer).to receive(:token).and_return('self-issued jwt')
        end

        [[:duo_agent_platform, generic_provider], [flow_feature, flow_provider]].each do |feature, provider|
          next unless provider

          create(:ai_feature_setting, feature: feature, provider: provider,
            self_hosted_model: (model if provider == :self_hosted))
        end
      end

      where(:workflow_definition, :flow_provider, :generic_provider, :destination) do
        'code_review/v1'          | :self_hosted | :vendored    | :self_hosted
        'code_review/v1'          | :self_hosted | :disabled    | :self_hosted
        'code_review/v1'          | :self_hosted | nil          | :self_hosted
        'code_review/v1'          | :self_hosted | :self_hosted | :self_hosted
        'code_review/v1'          | :vendored    | :self_hosted | :cloud
        'code_review/v1'          | nil          | :self_hosted | :cloud
        'code_review/v1'          | nil          | nil          | :cloud
        'developer/v1'            | :self_hosted | :vendored    | :self_hosted
        'secrets_fp_detection/v1' | :self_hosted | :vendored    | :self_hosted
      end

      with_them do
        it 'mints the token from the feature setting that chose the service URL' do
          expect(service.generate_workflow_token).to be_success

          expect(DuoWorkflowService::DuoWorkflow::Stub).to have_received(:new).with(expected_url, anything)
          expect(grpc_stub).to have_received(:generate_token)
            .with(anything, metadata: hash_including('authorization' => "Bearer #{expected_token}"), deadline: anything)
        end
      end
    end

    # This path forwards the resolver lists to the client as they are, so the resolver must
    # already have settled a name two rules reach: Create Issue and Create Work Item both
    # govern the MCP work item tool.
    context 'when two rules on the governing namespace reach one MCP spelling' do
      let(:group) { container.root_ancestor }

      before do
        stub_feature_flags(duo_mcp_tool_governance: group)
        create(:ai_tool_rule, namespace: group, tool_name: 'create_issue', web_access: :deny)
        create(:ai_tool_rule, namespace: group, tool_name: 'create_work_item', web_access: :allow)
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: token_data)
        )
      end

      it 'never hands the client a tool in more than one list' do
        captured = nil
        allow(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new) do |**kwargs|
          captured = kwargs
          workflow_client
        end

        service.generate_workflow_token

        expect(captured[:denied_tools]).to include('create_issue', 'gitlab_save_work_item')
        expect(captured[:pre_approved_tools]).to include('create_work_item')
        expect(captured[:pre_approved_tools] & captured[:denied_tools]).to be_empty
        expect(captured[:ask_tools] & captured[:denied_tools]).to be_empty
        expect(captured[:pre_approved_tools] & captured[:ask_tools]).to be_empty
      end
    end

    context 'when governance resolution succeeds' do
      before do
        allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
          allow(instance).to receive(:execute).and_return(
            ServiceResponse.success(payload: {
              pre_approved_tools: ['read_file'], denied_tools: [], ask_tools: ['run_command']
            })
          )
        end
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: token_data)
        )
      end

      it 'passes pre_approved, denied and ask tools from resolution service to client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(pre_approved_tools: ['read_file'], denied_tools: [], ask_tools: ['run_command'])
        ).and_return(workflow_client)

        service.generate_workflow_token
      end

      it 'asks the client to carry the ceiling' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(ceiling: true)
        ).and_return(workflow_client)

        service.generate_workflow_token
      end

      context 'when duo_workflow_governance_ceiling is disabled' do
        before do
          stub_feature_flags(duo_workflow_governance_ceiling: false)
        end

        it 'does not ask for the ceiling' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(ceiling: false)
          ).and_return(workflow_client)

          service.generate_workflow_token
        end
      end

      context 'when governance is not resolved for the token' do
        it 'does not ask for the ceiling' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(ceiling: false)
          ).and_return(workflow_client)

          service.generate_workflow_token(resolve_governance: false)
        end
      end

      context 'when the surface is ungoverned' do
        before do
          allow(Ai::ToolRules::GovernanceSurface).to receive(:ungoverned?).and_return(true)
        end

        it 'does not ask for the ceiling' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(pre_approved_tools: [], ceiling: false)
          ).and_return(workflow_client)

          service.generate_workflow_token
        end
      end

      context 'when governance resolution fails' do
        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
          end
        end

        it 'does not ask for the ceiling' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(pre_approved_tools: [], ceiling: false)
          ).and_return(workflow_client)

          service.generate_workflow_token
        end
      end

      context 'when the resolution payload predates the ask_tools key' do
        before do
          allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.success(payload: { pre_approved_tools: [], denied_tools: [] })
            )
          end
        end

        it 'defaults ask_tools to an empty array rather than passing nil' do
          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(ask_tools: [])
          ).and_return(workflow_client)

          service.generate_workflow_token
        end
      end

      it 'passes the project to ResolutionService when container is a project' do
        expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
          hash_including(project: container)
        ).and_call_original

        allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
          allow(instance).to receive(:execute).and_return(
            ServiceResponse.success(payload: { pre_approved_tools: [], denied_tools: [] })
          )
        end

        service.generate_workflow_token
      end

      context 'when the workflow environment is ambient (background)' do
        let(:workflow_definition) { 'developer/v1' }

        let(:service) do
          described_class.new(
            current_user: user,
            organization: container.organization,
            workflow_definition: workflow_definition,
            container: container,
            service_account: service_account,
            environment: 'ambient'
          )
        end

        it 'resolves the :background surface when the background-governance flag is enabled' do
          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(surface: :background)
          ).and_call_original

          service.generate_workflow_token
        end

        it 'resolves the :web surface when the background-governance flag is disabled' do
          stub_feature_flags(duo_workflow_background_tool_governance: false)

          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(surface: :web)
          ).and_call_original

          service.generate_workflow_token
        end
      end

      context 'when the workflow environment is a local surface' do
        let(:service) do
          described_class.new(
            current_user: user,
            organization: container.organization,
            workflow_definition: workflow_definition,
            container: container,
            service_account: service_account,
            environment: 'ide'
          )
        end

        it 'resolves the :ide surface when the local-governance flag is enabled' do
          expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
            hash_including(surface: :ide)
          ).and_call_original

          service.generate_workflow_token
        end

        it 'resolves nothing when the local-governance flag is disabled' do
          # Falling back to :web here governed an IDE session against web_access rules
          # while local governance was deliberately off. See gitlab-org/gitlab#622602.
          stub_feature_flags(duo_workflow_local_tool_governance: false)

          expect(Ai::ToolRules::ResolutionService).not_to receive(:new)

          service.generate_workflow_token
        end

        it 'sends empty lists on the wire, not absent keys', :aggregate_failures do
          # DWS reads empty allow, ask and deny as governance inactive. Absent keys or a
          # non-empty allow would both change that reading.
          stub_feature_flags(duo_workflow_local_tool_governance: false)

          expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
            hash_including(pre_approved_tools: [], ask_tools: [], denied_tools: [])
          ).and_return(workflow_client)

          service.generate_workflow_token
        end
      end

      it 'resolves the :web surface when no environment is given' do
        expect(Ai::ToolRules::ResolutionService).to receive(:new).with(
          hash_including(surface: :web)
        ).and_call_original

        service.generate_workflow_token
      end
    end

    context 'when resolution service fails' do
      before do
        allow_next_instance_of(Ai::ToolRules::ResolutionService) do |instance|
          allow(instance).to receive(:execute).and_return(
            ServiceResponse.error(message: 'something went wrong')
          )
        end
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: token_data)
        )
      end

      it 'falls back to empty pre_approved_tools and denied_tools' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(pre_approved_tools: [], denied_tools: [])
        ).and_return(workflow_client)

        service.generate_workflow_token
      end
    end

    context 'when container is nil' do
      subject(:service) do
        described_class.new(
          current_user: user,
          organization: container.organization,
          container: nil
        )
      end

      before do
        allow(workflow_client).to receive(:generate_token).and_return(
          ServiceResponse.success(payload: token_data)
        )
      end

      it 'passes empty pre_approved and denied tools to client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(pre_approved_tools: [], denied_tools: [])
        ).and_return(workflow_client)

        service.generate_workflow_token
      end

      it 'forwards a nil container to the client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          hash_including(container: nil)
        ).and_return(workflow_client)

        service.generate_workflow_token
      end
    end
  end

  describe '#generate_oauth_token_with_composite_identity_support' do
    context 'when composite identity is enforced on the service account' do
      it 'issues a token owned by the service account and scoped to the caller' do
        token = service.generate_oauth_token_with_composite_identity_support.payload[:oauth_access_token]

        expect(token.resource_owner_id).to eq(service_account.id)
        expect(token.scopes).to include("user:#{user.id}")
      end
    end

    context 'when service account does not have composite identity enforced' do
      before do
        service_account.update!(composite_identity_enforced: false)
      end

      it 'falls back to a token owned by the caller' do
        token = service.generate_oauth_token_with_composite_identity_support.payload[:oauth_access_token]

        expect(token.resource_owner_id).to eq(user.id)
        expect(token.scopes).not_to include("user:#{user.id}")
      end
    end

    context 'when the service account is itself the current user' do
      let(:user) { service_account }

      %w[scheduled system].each do |autonomous_source|
        context "with a #{autonomous_source} trigger_source" do
          let(:trigger_source) { autonomous_source.to_sym }

          it 'calls generate_autonomous_oauth_token, even with composite identity enforced' do
            expect(service).to receive(:generate_autonomous_oauth_token)
            expect(service).not_to receive(:generate_composite_oauth_token)

            service.generate_oauth_token_with_composite_identity_support
          end
        end
      end

      # An SA authenticating as itself is the normal state for any SA-owned token,
      # so routing must not change for callers that carry no autonomous trigger.
      context 'without a trigger_source, as when a service account calls the API' do
        it 'keeps the existing composite routing' do
          expect(service).to receive(:generate_composite_oauth_token)
          expect(service).not_to receive(:generate_autonomous_oauth_token)

          service.generate_oauth_token_with_composite_identity_support
        end
      end

      context 'with a human trigger_source' do
        let(:trigger_source) { :human }

        it 'keeps the existing composite routing' do
          expect(service).to receive(:generate_composite_oauth_token)
          expect(service).not_to receive(:generate_autonomous_oauth_token)

          service.generate_oauth_token_with_composite_identity_support
        end
      end
    end
  end

  describe '#generate_autonomous_oauth_token' do
    let(:trigger_source) { :scheduled }

    it 'delegates to CreateAutonomousOauthAccessTokenService with the trigger source' do
      expect_next_instance_of(
        ::Ai::DuoWorkflows::CreateAutonomousOauthAccessTokenService,
        service_account: service_account,
        organization: container.organization,
        container: container,
        trigger_source: :scheduled
      ) do |instance|
        expect(instance).to receive(:execute)
      end

      service.generate_autonomous_oauth_token
    end
  end

  describe '#already_scoped_for_ai_workflows?' do
    let(:ai_workflow_scopes) { ::Gitlab::Auth::AI_WORKFLOW_SCOPES + [::Gitlab::Auth::MCP_SCOPE] }
    let(:access_token) { instance_double(OauthAccessToken) }

    context 'when access_token is nil' do
      it 'returns false' do
        expect(service.already_scoped_for_ai_workflows?(nil)).to be(false)
      end
    end

    context 'when access_token.scopes returns nil' do
      it 'returns false' do
        allow(access_token).to receive(:scopes).and_return(nil)

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end
    end

    context 'when service account does not have composite identity enforced' do
      before do
        service_account.update!(composite_identity_enforced: false)
      end

      it 'returns true when the token has exactly the AI workflow scopes' do
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes)

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(true)
      end

      it 'returns false when the token has AI workflow scopes plus the dynamic user scope' do
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes + [:"user:#{user.id}"])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end

      it 'returns false when the token has extra scopes' do
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes + [:api])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end

      it 'returns false when the token has no scopes' do
        allow(access_token).to receive(:scopes).and_return([])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end
    end

    context 'when composite identity is enabled' do
      it 'returns true when the token has AI workflow scopes plus the dynamic user scope' do
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes + [:"user:#{user.id}"])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(true)
      end

      it 'returns false when the token has exactly the AI workflow scopes without the dynamic user scope' do
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes)

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end

      it 'returns false when the token has a different user in the dynamic scope' do
        other_user_id = user.id + 1
        allow(access_token).to receive(:scopes).and_return(ai_workflow_scopes + [:"user:#{other_user_id}"])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end

      it 'returns false when the token has no scopes' do
        allow(access_token).to receive(:scopes).and_return([])

        expect(service.already_scoped_for_ai_workflows?(access_token)).to be(false)
      end
    end

    context 'with a StatelessAccessToken JWT' do
      let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
      let_it_be(:organization) { create(:organization) }

      before do
        stub_feature_flags(duo_workflow_use_token_issuer: [service_account, user])
        allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
        allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
      end

      def stateless_access_token(identities: [{ kind: 'user', local_id: user.id }])
        jwt = ::Authn::Tokens::StatelessAccessToken.issue(
          user: service_account, organization: organization, ttl: 1.hour.to_i,
          scopes: ai_workflow_scopes, identities: identities
        ).plaintext_token
        ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)
      end

      it 'returns true when scopes match and the identity matches current_user' do
        expect(service.already_scoped_for_ai_workflows?(stateless_access_token)).to be(true)
      end

      it 'returns false when the identity does not match current_user' do
        other_user = create(:user)
        token = stateless_access_token(identities: [{ kind: 'user', local_id: other_user.id }])

        expect(service.already_scoped_for_ai_workflows?(token)).to be(false)
      end

      it 'returns false when scopes do not match exactly' do
        jwt = ::Authn::Tokens::StatelessAccessToken.issue(
          user: service_account, organization: organization, ttl: 1.hour.to_i,
          scopes: ai_workflow_scopes + [:api], identities: [{ kind: 'user', local_id: user.id }]
        ).plaintext_token
        token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)

        expect(service.already_scoped_for_ai_workflows?(token)).to be(false)
      end

      it 'returns false when the token is composite but composite identity is disabled for the service, ' \
        'rather than treating it as reusable without checking identity' do
        service_account.update!(composite_identity_enforced: false)
        token = stateless_access_token(identities: [{ kind: 'user', local_id: user.id }])

        expect(service.already_scoped_for_ai_workflows?(token)).to be(false)
      end

      it 'returns false when the service account enforces composite identity but the token carries no identities' do
        token = stateless_access_token(identities: [])

        expect(service.already_scoped_for_ai_workflows?(token)).to be(false)
      end

      context 'when composite identity is disabled and the token is non-composite' do
        before do
          service_account.update!(composite_identity_enforced: false)
        end

        def non_composite_token(for_user:)
          jwt = ::Authn::Tokens::StatelessAccessToken.issue(
            user: for_user, organization: organization, ttl: 1.hour.to_i, scopes: ai_workflow_scopes
          ).plaintext_token
          ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)
        end

        it 'returns true when the token subject is current_user' do
          expect(service.already_scoped_for_ai_workflows?(non_composite_token(for_user: user))).to be(true)
        end

        it 'returns false when the token subject is another user' do
          other_user = create(:user)

          expect(service.already_scoped_for_ai_workflows?(non_composite_token(for_user: other_user))).to be(false)
        end
      end

      it 'returns false when the token was minted for a different service account, ' \
        'even if the embedded identity matches current_user' do
        other_service_account = create(:user, :service_account, composite_identity_enforced: true)
        jwt = ::Authn::Tokens::StatelessAccessToken.issue(
          user: other_service_account, organization: organization, ttl: 1.hour.to_i,
          scopes: ai_workflow_scopes, identities: [{ kind: 'user', local_id: user.id }]
        ).plaintext_token
        token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)

        expect(service.already_scoped_for_ai_workflows?(token)).to be(false)
      end

      context 'when the service has no service account configured' do
        let(:service_without_service_account) do
          described_class.new(
            current_user: user,
            organization: container.organization,
            workflow_definition: workflow_definition,
            container: container,
            service_account: nil
          )
        end

        it 'still reuses a matching non-composite token, instead of treating nil as unequal to false' do
          jwt = ::Authn::Tokens::StatelessAccessToken.issue(
            user: user, organization: organization, ttl: 1.hour.to_i, scopes: ai_workflow_scopes
          ).plaintext_token
          token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)

          expect(service_without_service_account.already_scoped_for_ai_workflows?(token)).to be(true)
        end
      end
    end
  end

  describe '#duo_agent_platform_feature_setting' do
    context 'when workflow definition is secrets_fp_detection/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:secret_fp_detection_feature_setting) do
        create(:ai_feature_setting, :secret_vulnerability_fp_detection, self_hosted_model: model)
      end

      let(:workflow_definition) { 'secrets_fp_detection/v1' }

      it 'returns the secret fp detection feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(secret_fp_detection_feature_setting)
      end
    end

    context 'when workflow definition is resolve_sast_vulnerability/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:sast_vr_feature_setting) do
        create(:ai_feature_setting, :sast_vulnerability_resolution, self_hosted_model: model)
      end

      let(:workflow_definition) { 'resolve_sast_vulnerability/v1' }

      it 'returns the sast vulnerability resolution feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(sast_vr_feature_setting)
      end
    end

    context 'when workflow definition is sast_fp_detection/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:sast_fp_detection_feature_setting) do
        create(:ai_feature_setting, :sast_vulnerability_fp_detection, self_hosted_model: model)
      end

      let(:workflow_definition) { 'sast_fp_detection/v1' }

      it 'returns the sast fp detection feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(sast_fp_detection_feature_setting)
      end
    end

    context 'when workflow definition is code_review/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:review_merge_request_dap_feature_setting) do
        create(:ai_feature_setting, :review_merge_request_dap, self_hosted_model: model)
      end

      let_it_be(:review_merge_request_dap_deep_feature_setting) do
        create(:ai_feature_setting, :review_merge_request_dap_deep, self_hosted_model: model)
      end

      let(:workflow_definition) { 'code_review/v1' }

      it 'returns the review_merge_request_dap feature setting' do
        stub_feature_flags(duo_code_review_deep_flow: false)

        expect(service.duo_agent_platform_feature_setting).to eq(review_merge_request_dap_feature_setting)
      end

      it 'returns the review_merge_request_dap_deep feature setting when the deep flow is enabled' do
        stub_feature_flags(duo_code_review_deep_flow: user)

        expect(service.duo_agent_platform_feature_setting).to eq(review_merge_request_dap_deep_feature_setting)
      end

      context 'when a standard review is requested' do
        let(:service) do
          described_class.new(
            current_user: user,
            organization: container.organization,
            workflow_definition: workflow_definition,
            container: container,
            additional_context: [
              { 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(depth: 'standard') }
            ]
          )
        end

        it 'returns the review_merge_request_dap feature setting even when the deep flow is enabled' do
          stub_feature_flags(duo_code_review_deep_flow: user)

          expect(service.duo_agent_platform_feature_setting).to eq(review_merge_request_dap_feature_setting)
        end
      end
    end

    context 'when workflow definition is security_review/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:security_review_feature_setting) do
        create(:ai_feature_setting, :security_review, self_hosted_model: model)
      end

      let(:workflow_definition) { 'security_review/v1' }

      it 'returns the security_review feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(security_review_feature_setting)
      end
    end

    context 'when workflow definition is resolve_dependency_bump/experimental' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:resolve_dependency_bump_feature_setting) do
        create(:ai_feature_setting, :resolve_dependency_bump, self_hosted_model: model)
      end

      let(:workflow_definition) { 'resolve_dependency_bump/experimental' }

      it 'returns the resolve_dependency_bump feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(resolve_dependency_bump_feature_setting)
      end
    end

    context 'when workflow definition is bl_security/experimental' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:bl_security_feature_setting) do
        create(:ai_feature_setting, :bl_security, self_hosted_model: model)
      end

      # Literal on purpose: pins the reference the service maps to bl_security.
      let(:workflow_definition) { 'bl_security/experimental' }

      it 'returns the bl_security feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(bl_security_feature_setting)
      end

      it 'matches the shared foundational-flow reference constant' do
        expect(::Ai::Catalog::FoundationalFlow::BL_SECURITY_FLOW_REFERENCE).to eq(workflow_definition)
      end
    end

    context 'when workflow definition is developer/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let(:workflow_definition) { 'developer/v1' }

      let_it_be(:duo_developer_feature_setting) do
        create(:ai_feature_setting, :duo_developer, self_hosted_model: model)
      end

      it 'returns the duo_developer feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(duo_developer_feature_setting)
      end
    end

    context 'when workflow definition is recommend_reviewers/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:recommend_reviewers_assign_feature_setting) do
        create(:ai_feature_setting, :recommend_reviewers_assign, self_hosted_model: model)
      end

      let(:workflow_definition) { 'recommend_reviewers/v1' }

      it 'returns the recommend_reviewers_assign feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(recommend_reviewers_assign_feature_setting)
      end
    end

    context 'when workflow definition is risk_classification/v1' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:risk_classification_feature_setting) do
        create(:ai_feature_setting, :risk_classification, self_hosted_model: model)
      end

      let(:workflow_definition) { 'risk_classification/v1' }

      it 'returns the risk_classification feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(risk_classification_feature_setting)
      end
    end

    context 'when self-hosted feature setting exists' do
      let_it_be(:model) do
        create(:ai_self_hosted_model, model: :claude_3, identifier: 'claude-3-7-sonnet-20250219')
      end

      let_it_be(:duo_agent_platform_feature_setting) do
        create(:ai_feature_setting, :duo_agent_platform, self_hosted_model: model)
      end

      it 'returns the self-hosted feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(duo_agent_platform_feature_setting)
      end
    end

    context 'when instance level model selection exists' do
      let_it_be(:duo_agent_platform_feature_setting) do
        create(:instance_model_selection_feature_setting, feature: :duo_agent_platform)
      end

      it 'returns the instance level feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(duo_agent_platform_feature_setting)
      end
    end

    context 'when namespace level model selection exists', :saas do
      let_it_be(:user) { create(:user) }

      let_it_be(:duo_agent_platform_feature_setting) do
        create(:ai_namespace_feature_setting,
          namespace: container.namespace,
          feature: :duo_agent_platform,
          offered_model_ref: 'claude_sonnet_3_7_20250219')
      end

      before do
        container.namespace.add_developer(user)
      end

      it 'returns the namespace level feature setting' do
        expect(service.duo_agent_platform_feature_setting).to eq(duo_agent_platform_feature_setting)
      end
    end
  end
end
