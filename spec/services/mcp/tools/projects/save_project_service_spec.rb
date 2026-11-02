# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Projects::SaveProjectService, feature_category: :mcp_server do
  let(:create_tool) { instance_double(Mcp::Tools::Base::ApiTool, name: :create_project) }
  let(:tools) { [create_tool] }
  let(:service) { described_class.new(tools: tools) }

  describe '.tool_name' do
    it 'returns the aggregated tool name' do
      expect(described_class.tool_name).to eq('save_project')
    end
  end

  describe '#governed_containers' do
    let_it_be(:user) { create(:user, :with_namespace) }
    let_it_be(:group) { create(:group, path: 'governed-group') }
    let_it_be(:subgroup) { create(:group, parent: group, path: 'sub') }

    def governed(arguments)
      service.governed_containers(arguments.with_indifferent_access)
    end

    it 'governs by the group named with namespace_id' do
      expect(governed(namespace_id: group.id).containers).to eq([group])
    end

    it 'governs by the group named with namespace_path' do
      expect(governed(namespace_path: 'governed-group/sub').containers).to eq([subgroup])
    end

    it 'governs by a URL-encoded namespace path' do
      expect(governed(namespace_path: 'governed-group%2Fsub').containers).to eq([subgroup])
    end

    it 'does not count a personal namespace by ID' do
      expect(governed(namespace_id: user.namespace.id)).to be_none
    end

    it 'does not count a personal namespace by path' do
      expect(governed(namespace_path: user.namespace.full_path)).to be_none
    end

    it 'counts a namespace path that does not exist' do
      expect(governed(namespace_path: 'no-such-group')).not_to be_none
    end

    it 'counts a namespace ID that does not exist' do
      expect(governed(namespace_id: non_existing_record_id)).not_to be_none
    end

    it 'names nothing when no namespace is given' do
      expect(governed(name: 'My Project')).to be_none
    end
  end

  describe '#annotations' do
    it 'is a non-destructive write tool' do
      expect(service.annotations).to eq({ readOnlyHint: false, destructiveHint: false })
    end
  end

  describe '#input_schema' do
    it 'matches the advertised contract' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq(
        {
          type: 'object',
          properties: {
            name: {
              type: 'string',
              description: 'Name of the project. Required.'
            },
            path: {
              type: 'string',
              description: 'URL slug for the project.'
            },
            namespace_id: {
              type: 'integer',
              description: 'ID of the namespace (group or user) to create the project in.'
            },
            namespace_path: {
              type: 'string',
              description: 'Full path of the namespace. Alternative to namespace_id; provide one.'
            },
            description: {
              type: 'string',
              description: 'Description of the project.'
            },
            visibility: {
              type: 'string',
              enum: %w[private internal public],
              description: 'Visibility level.'
            },
            initialize_with_readme: {
              type: 'boolean',
              description: 'Create an initial README.md file.'
            },
            default_branch: {
              type: 'string',
              description: 'Default branch name.'
            },
            topics: {
              type: 'array',
              items: { type: 'string' },
              description: 'List of topics (tags) for the project.'
            },
            template_name: {
              type: 'string',
              description: 'Name of a built-in project template, for example "rails", "spring", or "express".'
            }
          },
          required: ['name']
        }
      )
    end

    it 'advertises only properties that reach the route allowlist' do
      route_params = ::API::Helpers::ProjectsHelpers.create_project_mcp_params
      schema_params = described_class.version_metadata('0.1.0')[:input_schema][:properties].keys
        .reject { |key| key == :namespace_path }

      expect(schema_params - route_params).to be_empty
    end
  end

  describe '#execute' do
    let(:request) { nil }
    let(:params) { { arguments: arguments } }
    let_it_be(:user) { create(:user) }
    let(:mock_response) do
      {
        content: [{ type: 'text', text: '{"id":1,"name":"My Project"}' }],
        structuredContent: { id: 1, name: 'My Project' },
        isError: false
      }
    end

    before do
      service.set_cred(current_user: user)
    end

    context 'with valid create arguments' do
      let(:arguments) { { name: 'My Project', description: 'A test project' } }

      it 'routes to the create tool' do
        expect(create_tool).to receive(:execute).with(request: request, params: params).and_return(mock_response)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be false
      end
    end

    context 'with extra arguments not in allowlist' do
      let(:arguments) { { name: 'My Project', import_url: 'https://example.com/repo.git' } }

      it 'filters out non-allowlisted params' do
        allow(create_tool).to receive(:execute) do |_request:, params:|
          expect(params[:arguments]).to include(name: 'My Project')
          expect(params[:arguments]).not_to have_key(:import_url)
          mock_response
        end

        service.execute(request: request, params: params)
      end
    end

    context 'with namespace_path as string path' do
      let_it_be(:group) { create(:group, path: 'my-group', guests: [user]) }
      let(:arguments) { { name: 'My Project', namespace_path: 'my-group' } }

      it 'resolves namespace to namespace_id' do
        allow(create_tool).to receive(:execute).and_return(mock_response)

        service.execute(request: request, params: params)

        expect(params[:arguments]).to include(namespace_id: group.id)
        expect(params[:arguments]).not_to have_key(:namespace_path)
      end
    end

    context 'with a URL-encoded namespace path' do
      let_it_be(:group) { create(:group, path: 'my-group', guests: [user]) }
      let(:arguments) { { name: 'My Project', namespace_path: 'my%2Dgroup' } }

      it 'decodes the path before resolving' do
        allow(create_tool).to receive(:execute).and_return(mock_response)

        service.execute(request: request, params: params)

        expect(params[:arguments]).to include(namespace_id: group.id)
        expect(params[:arguments]).not_to have_key(:namespace_path)
      end
    end

    context 'when namespace path does not exist' do
      let(:arguments) { { name: 'My Project', namespace_path: 'nonexistent-group' } }

      it 'returns the not found or inaccessible error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include("Namespace 'nonexistent-group' not found or inaccessible")
      end
    end

    context 'when namespace path exists but the user cannot read it' do
      let_it_be(:private_group) { create(:group, path: 'private-group') }
      let(:arguments) { { name: 'My Project', namespace_path: 'private-group' } }

      it 'returns the same error as a missing namespace' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include("Namespace 'private-group' not found or inaccessible")
      end
    end

    context 'when namespace_id does not exist' do
      let(:arguments) { { name: 'My Project', namespace_id: non_existing_record_id } }

      it 'returns an error instead of falling back to the personal namespace' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to include("Namespace '#{non_existing_record_id}' not found or inaccessible")
      end
    end

    context 'when namespace_id exists but the user cannot read it' do
      let_it_be(:private_group) { create(:group) }
      let(:arguments) { { name: 'My Project', namespace_id: private_group.id } }

      it 'returns the same error as a missing namespace' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to include("Namespace '#{private_group.id}' not found or inaccessible")
      end
    end

    context 'when both namespace_path and namespace_id are provided' do
      let_it_be(:group) { create(:group) }
      let(:arguments) { { name: 'My Project', namespace_path: 'some-group', namespace_id: group.id } }

      it 'rejects the ambiguous input' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('Provide namespace_path or namespace_id, not both')
      end
    end

    context 'when the create tool is not registered' do
      let(:arguments) { { name: 'My Project' } }
      let(:service) { described_class.new(tools: []) }

      it 'returns a tool-not-found error' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to include('save_project is not available on this GitLab instance')
      end
    end

    context 'with string-keyed arguments as delivered over MCP transport' do
      let_it_be(:group) { create(:group, guests: [user]) }
      let(:params) { { arguments: arguments.with_indifferent_access } }
      let(:arguments) { { 'name' => 'My Project', 'namespace_path' => group.path } }

      it 'still resolves namespace correctly' do
        allow(create_tool).to receive(:execute).and_return(mock_response)

        service.execute(request: request, params: params)

        expect(params[:arguments]).to include(namespace_id: group.id)
      end
    end
  end
end
