# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Todos::ListTodosService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:private_project) { create(:project, :private) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:todo) { create(:todo, user: user, project: project, target: issue) }

  let(:service) { described_class.new(name: 'list_todos') }

  before do
    service.set_cred(current_user: user)
  end

  describe 'class configuration' do
    it 'registers version 0.1.0' do
      expect(described_class.available_versions).to include('0.1.0')
    end

    it 'belongs to the core toolset' do
      expect(described_class.version_metadata('0.1.0')[:toolset]).to eq(:core)
    end

    it 'locks the description' do
      expect(described_class.version_metadata('0.1.0')[:description]).to eq(
        'List the to-do items of the authenticated user, such as review requests, ' \
          'assignments, and mentions. Returns pending to-do items unless state is set. Each to-do ' \
          'item includes its numeric id, action, target type, target URL, and the name and iid ' \
          'of its target.'
      )
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        required: [],
        properties: {
          state: {
            type: 'string',
            enum: %w[pending done],
            description: 'Filter by state.'
          },
          action: {
            type: 'string',
            enum: ::Types::TodoActionEnum.values.keys,
            description: 'Filter by the action that created the to-do item, for example ' \
              'review_requested. A mention is mentioned, or directly_addressed when the ' \
              'mention starts a paragraph.'
          },
          type: {
            type: 'string',
            enum: ::Types::TodoTargetEnum.values.keys,
            description: 'Filter by the type of the to-do item target, for example MERGEREQUEST or ISSUE.'
          },
          author_id: {
            type: 'integer',
            description: 'Filter by the numeric ID of the user who created the to-do item. ' \
              'Use get_user to look up the ID of a username.'
          },
          project_id: {
            type: 'string',
            description: 'Filter by project. ID or full path of the project.'
          },
          group_id: {
            type: 'string',
            description: 'Filter by group. ID or full path of the group.'
          },
          first: {
            type: 'integer',
            description: 'Number of to-do items to return after the cursor (forward pagination). Max 100.',
            minimum: 1,
            maximum: 100
          },
          after: {
            type: 'string',
            description: 'Cursor for forward pagination of to-do items. ' \
              'Use pageInfo.endCursor from a previous response.'
          }
        }
      })
    end
  end

  describe 'schema validation' do
    it 'rejects unknown arguments' do
      expect(service.input_schema[:additionalProperties]).to be(false)
    end

    it 'rejects an unknown state' do
      result = service.execute(request: nil, params: { arguments: { state: 'archived' } })

      expect(result[:content].first[:text]).to include('Validation error')
    end
  end

  describe '#execute' do
    let(:request) { instance_double(ActionDispatch::Request) }
    let(:params) { { arguments: {} } }

    it 'returns the to-do items connection', :aggregate_failures do
      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]['nodes'].pluck('id')).to contain_exactly(todo.id)
      expect(result[:structuredContent]).to have_key('pageInfo')
    end

    it 'instantiates the tool with the resolved version and arguments' do
      expect(Mcp::Tools::Todos::ListTodosTool).to receive(:new).with(
        current_user: user,
        params: params[:arguments],
        version: '0.1.0',
        access_token: nil
      ).and_call_original

      service.execute(request: request, params: params)
    end

    context 'when the project is not accessible' do
      let(:params) { { arguments: { project_id: private_project.full_path } } }

      it 'returns an error without revealing whether the project exists', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('not found or inaccessible')
      end
    end

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end
  end
end
