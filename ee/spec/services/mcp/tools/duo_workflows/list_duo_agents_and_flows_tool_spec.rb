# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::ListDuoAgentsAndFlowsTool, feature_category: :mcp_server do
  include Ai::Catalog::TestHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization, freeze: false) { create(:organization) }
  let_it_be(:group, freeze: false) { create(:group) }
  let_it_be(:user, freeze: false) { create(:user, developer_of: group) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }
  let_it_be(:other_project, freeze: false) { create(:project, group: group) }

  let(:params) { { project_id: project.full_path } }
  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }

  before do
    enable_ai_catalog
    allow(::Organizations::Organization).to receive(:default_organization).and_return(organization)
  end

  describe 'versioning' do
    it 'queries the configured catalog items connection' do
      expect(tool.operation_name).to eq('aiCatalogConfiguredItems')
    end
  end

  describe '#build_variables' do
    it 'resolves the project to a global ID and asks for both item types' do
      expect(tool.build_variables).to eq(
        projectId: project.to_global_id.to_s,
        itemTypes: %w[AGENT FLOW THIRD_PARTY_FLOW],
        includeChatAgents: true,
        first: 20
      )
    end

    context 'with a numeric project ID' do
      let(:params) { { project_id: project.id.to_s } }

      it 'resolves the same project' do
        expect(tool.build_variables).to include(projectId: project.to_global_id.to_s)
      end
    end

    context 'with an item type filter and cursor' do
      let(:params) { { project_id: project.full_path, item_type: 'flow', first: 5, after: 'cursor-1' } }

      it 'uses the GraphQL enum name and cursor pagination variables' do
        expect(tool.build_variables).to eq(
          projectId: project.to_global_id.to_s,
          itemTypes: %w[FLOW],
          includeChatAgents: false,
          first: 5,
          after: 'cursor-1'
        )
      end
    end

    context 'when the project is not visible to the user' do
      let(:params) { { project_id: create(:project).full_path } }

      it 'refuses to build a query for it' do
        expect { tool.build_variables }.to raise_error(StandardError, /not found or inaccessible/)
      end
    end
  end

  describe '#execute' do
    let_it_be(:flow_item, freeze: false) do
      create(:ai_catalog_flow, :with_released_version, project: project,
        name: 'Release notes', description: 'Writes release notes.')
    end

    let_it_be(:agent_item, freeze: false) do
      create(:ai_catalog_agent, project: project, name: 'Reviewer', description: 'Reviews merge requests.')
    end

    let_it_be(:flow_consumer, freeze: false) do
      create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: flow_item)
    end

    let_it_be(:agent_consumer, freeze: false) do
      create(:ai_catalog_item_consumer, project: project, item: agent_item)
    end

    it 'returns the enabled agents and flows, with a startable id only for flows' do
      result = tool.execute

      expect(result[:isError]).to be(false)
      expect(catalog_items(result)).to contain_exactly(
        {
          'name' => 'Release notes',
          'description' => 'Writes release notes.',
          'type' => 'flow',
          'foundational' => false,
          'workflow_definition' => nil,
          'can_start_session' => true,
          'ai_catalog_item_consumer_id' => flow_consumer.id
        },
        {
          'name' => 'Reviewer',
          'description' => 'Reviews merge requests.',
          'type' => 'agent',
          'foundational' => false,
          'workflow_definition' => nil,
          'can_start_session' => false,
          'ai_catalog_item_consumer_id' => nil
        }
      )
      expect(result.dig(:structuredContent, 'pageInfo')).to include('hasNextPage' => false)
      expect(result[:content]).to eq([{ type: 'text', text: Gitlab::Json.dump(result[:structuredContent]) }])
    end

    it 'withholds the id from a flow the user cannot execute' do
      unreleased = create(:ai_catalog_flow, project: project, name: 'Draft only')
      create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: unreleased)

      row = catalog_items(tool.execute).find { |item| item['name'] == 'Draft only' }

      expect(row).to include('can_start_session' => false, 'ai_catalog_item_consumer_id' => nil)
    end

    it 'lists external agents, which cannot be started either' do
      external = create(:ai_catalog_third_party_flow, project: project, name: 'External one')
      create(:ai_catalog_item_consumer, project: project, item: external)

      row = catalog_items(tool.execute).find { |item| item['name'] == 'External one' }

      expect(row).to include('type' => 'third_party_flow', 'can_start_session' => false,
        'ai_catalog_item_consumer_id' => nil)
    end

    it 'filters to a single item type' do
      result = execute_tool(item_type: 'flow')

      expect(item_names(result)).to contain_exactly('Release notes')
    end

    it 'omits items that are configured but disabled' do
      flow_consumer.update!(enabled: false)

      result = tool.execute

      expect(item_names(result)).to contain_exactly('Reviewer')
    end

    it 'omits items configured in another project' do
      create(:ai_catalog_item_consumer, project: other_project,
        item: create(:ai_catalog_agent, project: other_project, name: 'Elsewhere'))

      result = tool.execute

      expect(item_names(result)).not_to include('Elsewhere')
    end

    it 'truncates a long description' do
      flow_item.update!(description: 'a' * 300)

      result = tool.execute

      description = catalog_items(result).find { |item| item['type'] == 'flow' }['description']
      expect(description.length).to eq(described_class::DESCRIPTION_PREVIEW_LIMIT)
    end

    it 'paginates with the returned cursor' do
      first_page = execute_tool(first: 1)

      expect(catalog_items(first_page).size).to eq(1)
      expect(first_page.dig(:structuredContent, 'pageInfo', 'hasNextPage')).to be(true)

      second_page = execute_tool(first: 1, after: first_page.dig(:structuredContent, 'pageInfo', 'endCursor'))

      expect(item_names(second_page)).not_to eq(item_names(first_page))
    end

    context 'when a foundational agent arrives from both root fields' do
      let(:graphql_response) do
        {
          'data' => {
            'aiCatalogConfiguredItems' => {
              'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
              'nodes' => [
                {
                  'id' => 'gid://gitlab/Ai::Catalog::ItemConsumer/41',
                  'enabled' => true,
                  'userPermissions' => { 'executeAiCatalogItem' => true },
                  'item' => {
                    'name' => 'GitLab Duo', 'description' => 'Answers questions.',
                    'itemType' => 'AGENT', 'foundational' => true
                  }
                }
              ]
            },
            'aiFoundationalChatAgents' => {
              'nodes' => [{ 'name' => 'GitLab Duo', 'description' => 'Answers questions.',
                            'referenceWithVersion' => 'agentic_chat/v1' }]
            }
          }
        }
      end

      before do
        allow(GitlabSchema).to receive(:execute).and_return(graphql_response)
      end

      it 'lists it once, from the foundational field' do
        result = tool.execute

        expect(items(result)).to contain_exactly(
          {
            'name' => 'GitLab Duo',
            'description' => 'Answers questions.',
            'type' => 'agent',
            'foundational' => true,
            'workflow_definition' => 'agentic_chat/v1',
            'can_start_session' => false,
            'ai_catalog_item_consumer_id' => nil
          }
        )
      end
    end

    context 'when the caller can run foundational chat agents in the project' do
      let(:agents) { chat_agent_items(execute_tool({})).index_by { |item| item['workflow_definition'] } }

      before do
        stub_licensed_features(ai_features: true)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, project).and_return(true)
        allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(true)
      end

      it 'lists every agent but GitLab Duo itself as startable, with or without a flow version' do
        startable = agents.except(*described_class::DUO_CHAT_DEFINITIONS)

        expect(startable.keys).to include('analytics_agent/v1', 'duo_planner/v1', 'security_analyst_agent/v1')
        expect(startable.values.pluck('can_start_session')).to all(be(true))
      end

      it 'lists GitLab Duo itself as not startable, since list_duo_sessions leaves its sessions out' do
        expect(agents.fetch('chat')).to include('can_start_session' => false)
      end

      context 'without Ultimate' do
        before do
          stub_licensed_features(ai_features: false)
        end

        it 'lists an Ultimate-only agent as not startable, since starting it is refused' do
          expect(agents.fetch('security_analyst_agent/v1')).to include('can_start_session' => false)
          expect(agents.fetch('duo_planner/v1')).to include('can_start_session' => true)
        end
      end
    end

    context 'when the caller cannot start a foundational chat agent in the project' do
      where(:remote_flows_enabled, :can_use_agentic_chat, :can_use_duo_workflow) do
        false | true  | true
        true  | false | true
        true  | true  | false
      end

      with_them do
        before do
          project.update!(duo_remote_flows_enabled: remote_flows_enabled)
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(user, :access_duo_agentic_chat, project)
            .and_return(can_use_agentic_chat)
          allow(Ability).to receive(:allowed?).with(user, :duo_workflow, project).and_return(can_use_duo_workflow)
        end

        it 'lists none of them as startable' do
          agents = chat_agent_items(execute_tool({}))

          expect(agents).not_to be_empty
          expect(agents.pluck('can_start_session')).to all(be(false))
        end
      end
    end

    context 'when the caller is paginating' do
      it 'does not repeat the foundational chat agents on later pages' do
        first_page = execute_tool(first: 1)
        expect(chat_agent_items(first_page)).not_to be_empty

        cursor = first_page.dig(:structuredContent, 'pageInfo', 'endCursor')

        expect(chat_agent_items(execute_tool(first: 1, after: cursor))).to be_empty
      end
    end

    context 'when only flows are asked for' do
      it 'leaves the foundational chat agents out' do
        expect(chat_agent_items(execute_tool(item_type: 'flow'))).to be_empty
      end
    end

    context 'when the caller cannot read a consumer item' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          {
            'data' => {
              'aiCatalogConfiguredItems' => {
                'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil },
                'nodes' => [
                  { 'id' => 'gid://gitlab/Ai::Catalog::ItemConsumer/99', 'enabled' => true,
                    'userPermissions' => { 'executeAiCatalogItem' => true }, 'item' => nil }
                ]
              }
            }
          }
        )
      end

      it 'drops it rather than emitting a row of nulls' do
        expect(items(tool.execute)).to be_empty
      end
    end

    context 'when the connection is missing its nodes' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return(
          { 'data' => { 'aiCatalogConfiguredItems' => { 'pageInfo' => { 'hasNextPage' => false } } } }
        )
      end

      it 'reports that the operation returned no data' do
        result = tool.execute

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('Operation returned no data')
      end
    end

    context 'when the query returns errors' do
      before do
        allow(GitlabSchema).to receive(:execute).and_return({ 'errors' => [{ 'message' => 'Boom' }] })
      end

      it 'surfaces the error' do
        result = tool.execute

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('Boom')
      end
    end
  end

  def execute_tool(extra_params)
    described_class.new(current_user: user, params: params.merge(extra_params), access_token: nil).execute
  end

  def items(result)
    result.dig(:structuredContent, 'items')
  end

  # Foundational chat agents come from a fixed list the instance owns, so assertions about
  # what this project configured have to look past them.
  def chat_agent_items(result)
    items(result).select { |item| item['type'] == 'agent' && item['foundational'] }
  end

  def catalog_items(result)
    items(result) - chat_agent_items(result)
  end

  def item_names(result)
    catalog_items(result).map { |item| item['name'] }
  end
end
