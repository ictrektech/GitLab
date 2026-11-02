# frozen_string_literal: true

# Points GitLab at a duo-workflow-service, with or without one actually running.
#
# Use 'with duo workflow service stubbed' when you only want to test a feature
# that depends on Rails detecting that Duo Workflow Service is set up but the test can be
# implemented without interacting with this service. This shared context doesn't
# start a Duo Workflow Service process which helps to make the test more stable.
#
# "with duo workflow service" checks that the Duo Workflow Service is running and points
# GitLab at it. This is shared context when you want to test a feature that expects
# a real Duo Workflow Service to be running and interacting with it end-to-end.
RSpec.shared_context 'with duo workflow service stubbed' do
  include AgenticChatHelpers

  let(:model_definitions) do
    {
      'models' => [
        { 'name' => 'Claude Sonnet', 'identifier' => 'claude_sonnet_4_5_20250929' },
        { 'name' => 'Claude Haiku', 'identifier' => 'claude_haiku_4_5_20251001' }
      ],
      'unit_primitives' => [
        {
          'feature_setting' => 'duo_agent_platform_agentic_chat',
          'default_model' => 'claude_sonnet_4_5_20250929',
          'selectable_models' => %w[claude_sonnet_4_5_20250929 claude_haiku_4_5_20251001],
          'beta_models' => []
        }
      ]
    }
  end

  let(:model_definitions_response) { model_definitions.to_json }

  before do
    stub_feature_flags(use_generic_gitlab_api_tools: false,
      agentic_chat_flow_registry_migration: false, duo_workflow_use_token_issuer: false)

    allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive(:credits_available?).and_return(true)
    end

    stub_config(
      duo_workflow: {
        service_url: "0.0.0.0:#{Tasks::Gitlab::AiGateway::Utils.duo_workflow_service_port}",
        secure: false
      }
    )

    stub_request(:get, "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions")
      .to_return(
        status: 200,
        body: model_definitions_response,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
  end
end

RSpec.shared_context 'with duo workflow service' do
  include_context 'with duo workflow service stubbed'

  before do
    ensure_duo_workflow_service_running!
  end
end
