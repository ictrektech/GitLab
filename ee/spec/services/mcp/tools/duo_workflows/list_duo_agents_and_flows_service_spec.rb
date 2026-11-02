# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::ListDuoAgentsAndFlowsService, feature_category: :duo_agent_platform do
  let_it_be(:user) { create(:user) }

  let(:service) { described_class.new(name: 'list_duo_agents_and_flows') }

  before do
    service.set_cred(current_user: user)
  end

  describe 'class configuration' do
    it 'registers version 0.1.0' do
      expect(described_class.available_versions).to include('0.1.0')
    end

    it 'points callers at start_duo_session and ties startability to permission', :aggregate_failures do
      description = described_class.version_metadata('0.1.0')[:description].squish

      expect(description).to include('true for a flow you have permission to')
      expect(description).to include('you can run sessions in CI in this project. GitLab Duo itself')
      expect(description).to include('requires it is either left out or listed as not startable')
      expect(description).to include('startable flows carry the')
      expect(description).to include('ai_catalog_item_consumer_id that start_duo_session takes')
      expect(description).to include('passing its workflow_definition as agent')
    end

    it 'covers external agents and says when the chat agents are left out', :aggregate_failures do
      description = described_class.version_metadata('0.1.0')[:description]

      expect(description).to include('external agents')
      expect(description).to include('omitted unless agents are included')
    end

    it 'warns that a page can come back short of what was asked for' do
      description = described_class.version_metadata('0.1.0')[:description]

      expect(description).to include('Keep paging until hasNextPage is false')
    end

    it 'is read-only' do
      expect(described_class.version_metadata('0.1.0')[:annotations]).to eq(
        title: 'List Duo agents and flows',
        readOnlyHint: true,
        idempotentHint: true,
        openWorldHint: false
      )
    end

    it 'is registered as an EE GraphQL tool' do
      expect(::EE::Mcp::Tools::Manager::EE_GRAPHQL_TOOLS)
        .to include('list_duo_agents_and_flows' => described_class)
    end

    it 'resolves a namespace so tool governance rules reach it' do
      expect(described_class.container_arguments).to include(project: :project_id)
    end
  end

  describe 'input schema' do
    it 'requires a project and offers the catalog item types with cursor pagination' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        required: %w[project_id],
        properties: {
          project_id: {
            type: 'string',
            description: 'Numeric ID or full path of the project to list agents and flows for.'
          },
          item_type: {
            type: 'string',
            description: 'Return only one kind of item. All kinds are returned when omitted.',
            enum: %w[agent flow third_party_flow]
          },
          first: {
            type: 'integer',
            description: 'Number of agents and flows to return after the cursor (forward pagination). Max 100.',
            minimum: 1,
            maximum: 100
          },
          after: {
            type: 'string',
            description: 'Cursor for forward pagination of agents and flows. ' \
              'Use pageInfo.endCursor from a previous response.'
          }
        }
      })
    end

    it 'offers every catalog item type a project can configure' do
      expect(described_class::ITEM_TYPES).to match_array(
        [::Ai::Catalog::Item::AGENT_TYPE.to_s, ::Ai::Catalog::Item::FLOW_TYPE.to_s,
          ::Ai::Catalog::Item::THIRD_PARTY_FLOW_TYPE.to_s]
      )
    end
  end

  describe '#execute' do
    let(:request) { instance_double(ActionDispatch::Request) }
    let(:params) { { arguments: { project_id: '1' } } }

    it 'delegates to the GraphQL tool with the selected version and arguments' do
      expect(Mcp::Tools::DuoWorkflows::ListDuoAgentsAndFlowsTool).to receive(:new).with(
        current_user: user,
        params: params[:arguments],
        version: '0.1.0',
        access_token: nil
      ).and_call_original

      service.execute(request: request, params: params)
    end

    it 'rejects a request without a project' do
      result = service.execute(request: request, params: { arguments: {} })

      expect(result).to include(isError: true)
      expect(result[:content].first[:text]).to include('project_id')
    end

    it 'rejects item types that are not agents or flows' do
      result = service.execute(request: request, params: { arguments: { project_id: '1', item_type: 'mcp_server' } })

      expect(result).to include(isError: true)
      expect(result[:content].first[:text]).to include('item_type')
    end

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response' do
        result = service.execute(request: request, params: params)

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end
  end
end
