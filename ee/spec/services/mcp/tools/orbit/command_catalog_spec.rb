# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Orbit::CommandCatalog, :use_clean_rails_memory_store_caching, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, reporters: user) }

  let(:access_token) { nil }
  let(:context) { Mcp::Tools::RequestContext.new(current_user: user, access_token: access_token) }
  let(:grpc_client) { instance_double(Analytics::KnowledgeGraph::GrpcClient) }
  let(:commands) do
    [
      { name: 'query_graph', description: 'Query the graph.', parameters: { 'type' => 'object' } },
      { name: 'get_graph_schema', description: 'Get the schema.', parameters: { 'type' => 'object' } }
    ]
  end

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  before do
    stub_licensed_features(orbit: true)
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_feature_flags(orbit_promo_access_gate: false)
    allow(Analytics::KnowledgeGraph::GrpcClient).to receive(:new).and_return(grpc_client)
    allow(grpc_client).to receive(:list_agent_commands).and_return(commands)
  end

  describe '.tools_for' do
    subject(:tools) { described_class.tools_for(context) }

    it 'builds one tool for each Orbit command', :aggregate_failures do
      expect(tools.keys).to eq(%w[query_graph get_graph_schema])
      expect(tools.values).to all(be_a(Mcp::Tools::Orbit::CommandTool))
    end

    it 'asks the Orbit server for the commands with a short deadline' do
      tools

      expect(grpc_client).to have_received(:list_agent_commands).with(
        user: user, timeout: described_class::LIST_COMMANDS_TIMEOUT,
        request_context: having_attributes(source_type: Analytics::KnowledgeGraph::SourceType::MCP)
      )
    end

    it 'shares the cached command list between users' do
      other_user = create(:user)
      group.add_reporter(other_user)

      described_class.tools_for(context)
      described_class.tools_for(Mcp::Tools::RequestContext.new(current_user: other_user))

      expect(grpc_client).to have_received(:list_agent_commands).once
    end

    shared_examples 'no Orbit tools' do
      it 'returns no tools and does not call the Orbit server', :aggregate_failures do
        expect(tools).to eq({})
        expect(grpc_client).not_to have_received(:list_agent_commands)
      end
    end

    context 'when the user has no Orbit-enabled group' do
      before do
        Analytics::KnowledgeGraph::EnabledNamespace.delete_all
      end

      it_behaves_like 'no Orbit tools'
    end

    context 'when the instance license does not include Orbit' do
      before do
        stub_licensed_features(orbit: false)
      end

      it_behaves_like 'no Orbit tools'
    end

    context 'when a granular personal access token lacks the read_orbit permission' do
      let(:access_token) do
        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(:user),
          permissions: [::Authz::PermissionGroups::Assignable.for_permission(:execute_mcp_tool).first.name])
      end

      it_behaves_like 'no Orbit tools'
    end

    context 'when the Orbit server returns formatted text' do
      let(:commands) { { formatted_text: 'query_graph: ...' } }

      it 'returns no tools and does not cache the response', :aggregate_failures do
        2.times { expect(described_class.tools_for(context)).to eq({}) }

        expect(grpc_client).to have_received(:list_agent_commands).twice
      end
    end

    [
      Analytics::KnowledgeGraph::GrpcClient::ConnectionError,
      Analytics::KnowledgeGraph::GrpcClient::AuthorizationError
    ].each do |error_class|
      context "when the Orbit server raises #{error_class.name.demodulize}" do
        before do
          allow(grpc_client).to receive(:list_agent_commands).and_raise(error_class, 'failed')
          allow(Gitlab::KnowledgeGraph::Logger).to receive(:build).and_return(logger)
        end

        let(:logger) { instance_double(Gitlab::KnowledgeGraph::Logger, error: nil) }

        it 'returns no tools and logs the error', :aggregate_failures do
          expect(tools).to eq({})
          expect(logger).to have_received(:error).with(
            message: 'MCP Orbit list_agent_commands error', Labkit::Fields::ERROR_MESSAGE => 'failed'
          )
        end
      end
    end
  end
end
