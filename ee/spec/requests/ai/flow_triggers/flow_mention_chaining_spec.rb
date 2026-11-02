# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Flow-to-flow mention chaining', :sidekiq_inline, feature_category: :dap_triggers do
  include ApiHelpers

  include_context 'without ai usage quota check'

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :small_repo, group: group) }
  let_it_be(:human) { create(:user, maintainer_of: project) }
  let_it_be(:issue) { create(:issue, project: project) }

  let_it_be(:oauth_application) do
    create(:oauth_application, name: 'Duo Workflow', scopes: %w[ai_workflows mcp user:*])
  end

  # The flow that posts the mention, started by the human.
  let_it_be(:parent_service_account) { create(:composite_identity_service_account_for_project, project: project) }
  let_it_be(:parent_workflow) { create(:duo_workflows_workflow, project: project, user: human) }
  let_it_be(:parent_token) do
    create(:oauth_access_token,
      organization: project.organization,
      application: oauth_application,
      resource_owner: parent_service_account,
      expires_in: 1.hour,
      scopes: ::Gitlab::Auth::AI_WORKFLOW_SCOPES + ["user:#{human.id}"])
  end

  # The mentioned flow is Duo Developer, which replies through the messaging adapter.
  # Mentions resolve through the user's personal namespace.
  let_it_be(:developer_service_account) do
    create(:composite_identity_service_account_for_project, :with_namespace, project: project)
  end

  let_it_be_with_reload(:developer_item) do
    create(:ai_catalog_item, :flow, :public, foundational_flow_reference: 'developer/v1',
      organization: group.organization)
  end

  let_it_be(:developer_group_consumer) do
    create(:ai_catalog_item_consumer, group: group, item: developer_item,
      service_account: developer_service_account, enabled: true, locked: true)
  end

  let_it_be(:developer_project_consumer) do
    create(:ai_catalog_item_consumer, project: project, item: developer_item,
      parent_item_consumer: developer_group_consumer, enabled: true, locked: true)
  end

  let_it_be(:developer_flow_enabled) do
    create(:ai_catalog_enabled_foundational_flow, :for_project, project: project, catalog_item: developer_item)
  end

  let_it_be(:developer_trigger) do
    create(:ai_flow_trigger, :for_catalog_consumer, project: project,
      ai_catalog_item_consumer: developer_project_consumer,
      event_types: [::Ai::FlowTrigger::EVENT_TYPES[:mention]])
  end

  before_all do
    add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :active, namespace: nil)
    create(:gitlab_subscription_user_add_on_assignment, user: human, add_on_purchase: add_on_purchase)

    developer_item.latest_version.update!(release_date: Time.current)
    project.project_setting.update!(duo_features_enabled: true, duo_remote_flows_enabled: true,
      duo_foundational_flows_enabled: true)
    ::Ai::Setting.for_organization(project.organization).update!(duo_workflow_oauth_application: oauth_application)
  end

  before do
    stub_feature_flags(duo_workflow_use_token_issuer: false)
    stub_licensed_features(ai_workflows: true, ai_features: true)
    stub_duo_runner_available(true)
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)

    # The AI Gateway, the Duo Workflow Service and the CI workload are outside the chain under test.
    allow(::Ai::DuoWorkflows::GenerateWorkflowTitleWorker).to receive(:perform_async)
    allow_next_instance_of(::Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
      allow(client).to receive(:generate_token).and_return(ServiceResponse.success(payload: { token: 'dws-token' }))
    end
    allow_next_instance_of(::Ai::DuoWorkflows::StartWorkflowService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: { workload_id: 1 }))
    end
  end

  def mention_developer_as_parent_flow
    post api("/projects/#{project.id}/issues/#{issue.iid}/notes", oauth_access_token: parent_token),
      params: { body: "@#{developer_service_account.username} please implement this" },
      headers: { 'X-Gitlab-Duo-Workflow-Id' => parent_workflow.id.to_s }

    expect(response).to have_gitlab_http_status(:created)

    Note.find(json_response['id'])
  end

  def finish_with_message(workflow, message)
    # Keep the final message on the plain checkpoint: checkpoint storage is not under test.
    stub_feature_flags(duo_workflow_read_incremental_checkpoints: false)

    workflow.start!
    create(:duo_workflows_checkpoint, workflow: workflow, project: project,
      checkpoint: { 'channel_values' => { 'ui_chat_log' => [{ 'message_type' => 'agent', 'content' => message }] } })
    workflow.finish!
  end

  def developer_replies
    issue.notes.user.where(author: developer_service_account)
  end

  it 'starts the mentioned flow as a child that acts for the human', :aggregate_failures do
    note = nil

    expect { note = mention_developer_as_parent_flow }.to change { parent_workflow.child_workflows.count }.by(1)

    expect(note.author).to eq(parent_service_account)

    child = parent_workflow.child_workflows.sole
    expect(child).to be_triggered_by_flow
    expect(child.user).to eq(human)
    expect(child.service_account).to eq(developer_service_account)

    token = OauthAccessToken.where(resource_owner: developer_service_account).sole
    expect(token.scopes).to include("user:#{human.id}")
  end

  it 'posts the reply to the mention once the child flow finishes', :aggregate_failures do
    note = mention_developer_as_parent_flow
    child = parent_workflow.child_workflows.sole

    expect { finish_with_message(child, 'Implemented in a new merge request.') }
      .to change { developer_replies.count }.by(1)

    reply = developer_replies.sole
    expect(reply.discussion_id).to eq(note.discussion_id)
    expect(reply.note).to include('Implemented in a new merge request.', child.web_url)
  end

  context 'when the chain is at the depth limit' do
    before do
      # The parent is the root of the chain, so its child would already be one hop too deep.
      stub_const("#{::Ai::FlowTriggers::CallerContext}::MAX_TRIGGER_DEPTH", 1)
    end

    it 'does not start the mentioned flow and replies with an error', :aggregate_failures do
      expect { mention_developer_as_parent_flow }.not_to change { ::Ai::DuoWorkflows::Workflow.count }

      expect(developer_replies.sole.note).to eq(s_('DuoCodeReview|Something went wrong. Please try again.'))
    end
  end
end
