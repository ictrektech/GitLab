# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group > Settings > GitLab Duo > Additional context', :js, :saas,
  feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group, owners: user) }
  let_it_be(:organization) { group.organization }

  let(:none_connected_copy) do
    s_('DuoAgentPlatform|Experiment. Connect to tools your team already uses, such as Jira or Linear. ' \
      'None connected yet.')
  end

  let(:two_connected_copy) do
    format(
      s_('DuoAgentPlatform|Experiment. %{first} and %{second} connected. Agents can use both.'),
      first: 'Atlassian', second: 'Linear'
    )
  end

  before_all do
    create(:gitlab_subscription, :ultimate, namespace: group)
    add_on_purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
    create(:gitlab_subscription_user_add_on_assignment, add_on_purchase: add_on_purchase, user: user)
    group.namespace_settings.update!(duo_features_enabled: true, duo_custom_agents_enabled: true)
    group.ai_settings.update!(duo_agent_platform_enabled: true, duo_workflow_mcp_enabled: true)
  end

  before do
    stub_licensed_features(code_suggestions: true, ai_features: true, ai_catalog: true)
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_request(:get, "https://cloud.gitlab.com/ai/v1/models%2Fdefinitions")
      .to_return(status: 200, body: { 'models' => [], 'unit_primitives' => [] }.to_json,
        headers: { 'Content-Type' => 'application/json' })
    # The seat check would otherwise call CustomersDot.
    allow_next_instance_of(::Ai::UsageQuotaService) do |service|
      allow(service).to receive(:execute).and_return(ServiceResponse.success)
    end
    # Stub the entitlement seams so the real :read_ai_catalog_mcp_server policy grant is exercised.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(true)
    sign_in(user)
  end

  def connect_agent_using(server_ids)
    agent = create(:ai_catalog_agent, organization: organization)
    create(:ai_catalog_agent_version, item: agent, definition: {
      'system_prompt' => 'Test prompt',
      'tools' => [],
      'user_prompt' => '',
      'mcp_servers' => server_ids
    })
    create(:ai_catalog_item_consumer, group: group, item: agent)
  end

  it 'shows IDE access as on and no MCP tools connected' do
    visit group_settings_gitlab_duo_configuration_index_path(group)

    within_testid('additional-context-section') do
      expect(page).to have_css('[data-testid="readiness-section-title"]', text: 'Additional context')
      expect(page).to have_content(none_connected_copy)
      expect(page).to have_link(s_('DuoAgentPlatform|How to connect'))
      expect(page).to have_css('[data-testid="ide-access-toggle"] button[aria-checked="true"]')
    end
  end

  context 'when the group has agents using MCP servers' do
    before do
      linear = create(:ai_catalog_mcp_server, organization: organization, name: 'Linear')
      atlassian = create(:ai_catalog_mcp_server, organization: organization, name: 'Atlassian')

      connect_agent_using([linear.id, atlassian.id])
      connect_agent_using([atlassian.id])
    end

    it 'names each connected server once and links to the servers page' do
      visit group_settings_gitlab_duo_configuration_index_path(group)

      within_testid('group-mcp-row') do
        expect(page).to have_content(two_connected_copy)
        expect(page).to have_link(s_('DuoAgentPlatform|View tools'), href: group_automate_mcp_servers_path(group))
      end
    end
  end
end
