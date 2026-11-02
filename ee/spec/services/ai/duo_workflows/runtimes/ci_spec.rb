# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::Runtimes::Ci, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:service_account) { create(:user, :service_account) }

  let(:workflow) do
    create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
      workflow_definition: 'developer/v1')
  end

  let(:params_overrides) { {} }
  let(:context) { {} }
  let(:start_result) { ServiceResponse.success(payload: { workload_id: 123 }) }
  let(:context_service) do
    instance_double(
      ::Ai::DuoWorkflows::WorkflowContextGenerationService,
      generate_oauth_token_with_composite_identity_support: ServiceResponse.success(payload: {
        oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
      }),
      generate_workflow_token: ServiceResponse.success(payload: { token: 'workflow-token' }),
      duo_agent_platform_feature_setting: nil
    )
  end

  subject(:result) do
    described_class.new(workflow, params_overrides: params_overrides, context: context).execute
  end

  before do
    allow(::Ai::ServiceAccountMemberAddService).to receive(:new).and_return(
      instance_double(::Ai::ServiceAccountMemberAddService, execute: ServiceResponse.success)
    )
    allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(context_service)
    allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_return({})
    allow(::Ai::DuoWorkflows::StartWorkflowService).to receive(:new).and_return(
      instance_double(::Ai::DuoWorkflows::StartWorkflowService, execute: start_result)
    )
    allow(::Ai::DuoWorkflows::ResumeWorkflowService).to receive(:new).and_return(
      instance_double(::Ai::DuoWorkflows::ResumeWorkflowService, execute: start_result)
    )
  end

  context 'with additional context' do
    let(:additional_context) do
      [{ 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(depth: 'standard') }]
    end

    let(:context) { { additional_context: additional_context } }

    it 'passes it to the context service, which picks the model setting' do
      result

      expect(::Ai::DuoWorkflows::WorkflowContextGenerationService).to have_received(:new)
        .with(hash_including(additional_context: additional_context))
    end
  end

  it 'binds the minted workflow token to the workflow it is issued for' do
    result

    expect(context_service).to have_received(:generate_workflow_token)
      .with(hash_including(workflow_id: workflow.id))
  end

  context 'on a first run' do
    it 'provisions the service account and starts the workflow', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to include(workload_id: 123)
      expect(::Ai::ServiceAccountMemberAddService).to have_received(:new).with(project, service_account)
      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new)
    end

    it 'passes the minted tokens and defaulted source branch' do
      result

      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow,
        params: hash_including(
          workflow_oauth_token: 'oauth-token',
          workflow_service_token: 'workflow-token',
          source_branch: project.default_branch_or_main
        )
      )
    end
  end

  context 'with a foundational flow whose version is feature-flag gated' do
    let(:workflow_definition) { 'workplan/v1' }
    let(:workflow) do
      create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
        workflow_definition: workflow_definition)
    end

    let(:context_service) do
      instance_double(
        ::Ai::DuoWorkflows::WorkflowContextGenerationService,
        generate_oauth_token_with_composite_identity_support: ServiceResponse.success(payload: {
          oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
        }),
        duo_agent_platform_feature_setting: nil
      )
    end

    before do
      allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_call_original
      allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(context_service)
    end

    where(:workplan_score, :flow_version) do
      [
        [true, '1.1.0'],
        [false, '1.0.0']
      ]
    end

    with_them do
      it 'binds the token to the same flow it starts the workflow with', :aggregate_failures do
        stub_feature_flags(workplan_score: workplan_score)
        expect(context_service).to receive(:generate_workflow_token)
          .with(flow_config_id: 'workplan', flow_version: flow_version, flow_config_schema_version: 'v1',
            flow_config: nil, workflow_id: workflow.id)
          .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

        result

        expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(
            flow_config_id: 'workplan', flow_version: flow_version, flow_config_schema_version: 'v1'
          )
        )
      end
    end

    context 'with a foundational flow whose schema version is feature-flag gated' do
      let(:workflow_definition) { 'fix_pipeline/v1' }

      where(:fix_pipeline_experimental, :schema_version, :flow_version) do
        [
          [true, 'experimental', '1.0.0'],
          [false, 'v1', '1.0.4']
        ]
      end

      with_them do
        it 'binds the token to the same schema version it starts the workflow with', :aggregate_failures do
          stub_feature_flags(fix_pipeline_experimental: fix_pipeline_experimental)
          expect(context_service).to receive(:generate_workflow_token)
            .with(flow_config_id: 'fix_pipeline', flow_version: flow_version,
              flow_config_schema_version: schema_version, flow_config: nil, workflow_id: workflow.id)
            .and_return(ServiceResponse.success(payload: { token: 'workflow-token' }))

          result

          expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
            workflow: workflow,
            params: hash_including(
              flow_config_id: 'fix_pipeline', flow_version: flow_version, flow_config_schema_version: schema_version
            )
          )
        end
      end
    end
  end

  context 'on a continuation' do
    let(:workflow) do
      create(:duo_workflows_workflow, :input_required, user: user, project: project, service_account: service_account,
        workflow_definition: 'developer/v1')
    end

    it 'resumes instead of starting' do
      expect(result).to be_success
      expect(::Ai::DuoWorkflows::ResumeWorkflowService).to have_received(:new)
      expect(::Ai::DuoWorkflows::StartWorkflowService).not_to have_received(:new)
    end

    context 'when the flow version resolver changed since the session started' do
      let(:workflow) do
        create(:duo_workflows_workflow, :input_required, user: user, project: project,
          service_account: service_account, workflow_definition: 'workplan/v1',
          flow_metadata_json: { flow_id: 'workplan', schema_version: 'v1', flow_version: '1.1.0',
                                flow_version_constraint: '1.1.0' }.to_json)
      end

      before do
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_call_original
        stub_feature_flags(workplan_score: false)
      end

      it 'binds the token and the resumed job to the version the session runs', :aggregate_failures do
        result

        expect(context_service).to have_received(:generate_workflow_token).with(
          hash_including(flow_config_id: 'workplan', flow_version: '1.1.0', flow_config_schema_version: 'v1')
        )
        expect(::Ai::DuoWorkflows::ResumeWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(flow_config_id: 'workplan', flow_version: '1.1.0', flow_config_schema_version: 'v1')
        )
      end
    end

    context 'when a code review started with a standard depth' do
      let(:standard_flow) do
        { flow_config_id: 'code_review', flow_config_schema_version: 'v1', flow_version: '^4.0.0' }
      end

      let(:workflow) do
        create(:duo_workflows_workflow, :input_required, user: user, project: project,
          service_account: service_account, workflow_definition: 'code_review/v1',
          flow_metadata_json: ::Ai::DuoWorkflows::FlowMetadata.started(standard_flow))
      end

      before do
        allow(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).to receive(:call).and_call_original
        stub_feature_flags(duo_code_review_deep_flow: true, duo_code_review_standard_structured_findings: true)
      end

      it 'resumes on that version although the resolver now picks the deep flow', :aggregate_failures do
        expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver.call('code_review/v1', project, user: user))
          .to include(flow_config_id: 'deep_code_review')

        result

        expect(context_service).to have_received(:generate_workflow_token).with(hash_including(standard_flow))
        expect(::Ai::DuoWorkflows::ResumeWorkflowService).to have_received(:new)
          .with(workflow: workflow, params: hash_including(standard_flow))
      end
    end
  end

  context 'with params_overrides' do
    let(:params_overrides) { { goal: 'Please continue', human_approval: true } }

    it 'merges them over the base params' do
      result

      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow,
        params: hash_including(goal: 'Please continue', human_approval: true)
      )
    end

    context 'with a key outside the allowlist' do
      let(:params_overrides) { { workflow_oauth_token: 'forged', source_branch: 'other' } }

      it 'drops it rather than clobbering base params', :aggregate_failures do
        result

        expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(
            workflow_oauth_token: 'oauth-token',
            source_branch: project.default_branch_or_main
          )
        )
      end
    end
  end

  context 'with context' do
    let(:context) { { event_type: 'mention', triggering_conversation: 'Why?', client_context: nil } }

    it 'merges it into the start params without nil keys', :aggregate_failures do
      result

      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow,
        params: hash_including(event_type: 'mention', triggering_conversation: 'Why?')
      )
      expect(::Ai::DuoWorkflows::StartWorkflowService).not_to have_received(:new).with(
        workflow: workflow, params: hash_including(:client_context)
      )
    end

    context 'with a key the runtime builds' do
      let(:context) { { workflow_oauth_token: 'forged', source_branch: 'other' } }

      it 'keeps the base param rather than clobbering it' do
        result

        expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
          workflow: workflow,
          params: hash_including(
            workflow_oauth_token: 'oauth-token',
            source_branch: project.default_branch_or_main
          )
        )
      end
    end
  end

  context 'with a source_branch' do
    subject(:result) { described_class.new(workflow, source_branch: 'feature').execute }

    it 'uses it instead of the default' do
      result

      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow, params: hash_including(source_branch: 'feature')
      )
    end
  end

  context 'when the foundational flow declares report_artifacts' do
    let(:workflow) do
      create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
        workflow_definition: 'code_review/v1')
    end

    let(:report_artifacts) { { 'sast' => ['gl-sast-report.json'] } }

    before do
      allow(workflow).to receive(:foundational_flow).and_return(
        instance_double(::Ai::Catalog::FoundationalFlow, report_artifacts: report_artifacts)
      )
    end

    it 'reads them from the session' do
      result

      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow, params: hash_including(report_artifacts: report_artifacts)
      )
    end
  end

  context 'when the session runs a custom catalog flow' do
    let_it_be(:item) { create(:ai_catalog_flow, project: project) }
    let(:flow_definition) { item.latest_version.definition.except('yaml_definition') }

    let(:workflow) do
      create(:duo_workflows_workflow, :created, user: user, project: project, service_account: service_account,
        workflow_definition: ::Ai::DuoWorkflows::Workflow::AI_CATALOG_AGENT_FLOW_TYPE,
        ai_catalog_item_version: item.latest_version)
    end

    it 'reads the flow config from the item version, not the foundational resolver', :aggregate_failures do
      result

      expect(::Ai::DuoWorkflows::FoundationalFlowStartParamsResolver).not_to have_received(:call)
      expect(::Ai::DuoWorkflows::StartWorkflowService).to have_received(:new).with(
        workflow: workflow,
        params: hash_including(flow_config: flow_definition, flow_config_schema_version: 'v1')
      )
    end

    it 'binds the workflow token to the flow config without a schema version claim' do
      result

      expect(context_service).to have_received(:generate_workflow_token)
        .with(flow_config_id: nil, flow_version: nil, flow_config_schema_version: nil, flow_config: flow_definition,
          workflow_id: workflow.id)
    end
  end

  context 'when the workflow is not project-level' do
    let(:workflow) do
      create(:duo_workflows_workflow, :created, user: user, namespace: project.namespace,
        service_account: service_account, workflow_definition: 'developer/v1')
    end

    it 'returns :invalid_ci_session', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_ci_session)
    end
  end

  context 'when the workflow has no service account' do
    let(:workflow) do
      create(:duo_workflows_workflow, :created, user: user, project: project,
        service_account: nil, workflow_definition: 'developer/v1')
    end

    it 'returns :invalid_ci_session', :aggregate_failures do
      expect(result).to be_error
      expect(result.reason).to eq(:invalid_ci_session)
    end
  end

  context 'when service account provisioning fails' do
    before do
      allow(::Ai::ServiceAccountMemberAddService).to receive(:new).and_return(
        instance_double(::Ai::ServiceAccountMemberAddService,
          execute: ServiceResponse.error(message: 'member add failed'))
      )
    end

    it 'returns :service_account_error without starting the run', :aggregate_failures do
      expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:service_account_error)
    end
  end

  context 'when the service account enforces composite identity' do
    before do
      allow(service_account).to receive(:composite_identity_enforced?).and_return(true)
      ai_settings = instance_double(::Ai::Setting, duo_workflow_oauth_application: oauth_application)
      allow(::Ai::Setting).to receive(:for_organization_read_only).and_return(ai_settings)
      allow(::Gitlab::Auth::Identity).to receive(:link_from_web_request)
    end

    let(:oauth_application) { instance_double(Doorkeeper::Application) }

    it 'links the composite identity before provisioning', :aggregate_failures do
      expect(result).to be_success
      expect(::Gitlab::Auth::Identity).to have_received(:link_from_web_request).with(
        service_account: service_account, scoped_user: user
      )
    end

    context 'without an OAuth application configured' do
      let(:oauth_application) { nil }

      it 'skips the identity link and still runs', :aggregate_failures do
        expect(result).to be_success
        expect(::Gitlab::Auth::Identity).not_to have_received(:link_from_web_request)
      end
    end
  end

  context 'when the oauth token cannot be generated' do
    before do
      allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(
        instance_double(
          ::Ai::DuoWorkflows::WorkflowContextGenerationService,
          generate_oauth_token_with_composite_identity_support: ServiceResponse.error(message: 'no token')
        )
      )
    end

    it 'returns :invalid_oauth_token without starting the run', :aggregate_failures do
      expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:invalid_oauth_token)
    end

    it 'returns the generic message and logs the underlying one', :aggregate_failures do
      allow(::Gitlab::AppLogger).to receive(:warn)

      expect(result.message).to eq('Could not obtain authentication token')
      expect(::Gitlab::AppLogger).to have_received(:warn).with(
        hash_including(
          Labkit::Fields::ERROR_MESSAGE => 'no token',
          workflow_id: workflow.id,
          token_error_reason: :invalid_oauth_token
        )
      )
    end
  end

  context 'when the workflow token cannot be generated' do
    before do
      allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(
        instance_double(
          ::Ai::DuoWorkflows::WorkflowContextGenerationService,
          generate_oauth_token_with_composite_identity_support: ServiceResponse.success(payload: {
            oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
          }),
          generate_workflow_token: ServiceResponse.error(message: 'no token')
        )
      )
    end

    it 'returns :invalid_duo_workflow_token without starting the run', :aggregate_failures do
      expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

      expect(result).to be_error
      expect(result.reason).to eq(:invalid_duo_workflow_token)
    end

    it 'returns the generic message and logs the underlying one', :aggregate_failures do
      allow(::Gitlab::AppLogger).to receive(:warn)

      expect(result.message).to eq('Could not obtain Duo Workflow token')
      expect(::Gitlab::AppLogger).to have_received(:warn).with(
        hash_including(
          Labkit::Fields::ERROR_MESSAGE => 'no token',
          workflow_id: workflow.id,
          token_error_reason: :invalid_duo_workflow_token
        )
      )
    end
  end

  context 'when token generation raises' do
    using RSpec::Parameterized::TableSyntax

    let(:error) { ActiveRecord::RecordInvalid.new }
    let(:oauth_token_result) do
      ServiceResponse.success(payload: {
        oauth_access_token: instance_double(Doorkeeper::AccessToken, plaintext_token: 'oauth-token')
      })
    end

    where(:raising_method, :reason, :message) do
      :generate_oauth_token_with_composite_identity_support | :invalid_oauth_token |
        'Could not obtain authentication token'
      :generate_workflow_token | :invalid_duo_workflow_token | 'Could not obtain Duo Workflow token'
    end

    with_them do
      before do
        context_service = instance_double(
          ::Ai::DuoWorkflows::WorkflowContextGenerationService,
          generate_oauth_token_with_composite_identity_support: oauth_token_result,
          generate_workflow_token: ServiceResponse.success(payload: { token: 'workflow-token' })
        )
        allow(context_service).to receive(raising_method).and_raise(error)
        allow(::Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(context_service)
        allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'tracks the exception and returns the token reason without starting the run', :aggregate_failures do
        expect(::Ai::DuoWorkflows::StartWorkflowService).not_to receive(:new)

        expect(result).to be_error
        expect(result.reason).to eq(reason)
        expect(result.message).to eq(message)
        expect(::Gitlab::ErrorTracking).to have_received(:track_exception).with(error, workflow_id: workflow.id)
      end
    end
  end
end
