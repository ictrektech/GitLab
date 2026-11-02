# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat -- JSON-RPC has single path for method invocation
RSpec.describe API::Mcp, 'List tools request', feature_category: :mcp_server do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be(:access_token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }
  let_it_be(:gitlab_credits) { create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :self_managed) }

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true, duo_features_enabled: true)
    stub_ee_application_setting(elasticsearch_search: true)
    allow(::Search::Zoekt).to receive(:search_enabled?).and_return(true)

    manager = ObjectSpace.each_object(Mcp::Tools::Manager).first
    manager.instance_variable_set(:@mcp_routes, nil)
    manager.instance_variable_set(:@tools, nil)
    manager.instance_variable_set(:@api_tools, nil)
    manager.instance_variable_set(:@aggregated_api_tools, nil)
  end

  describe 'POST /mcp with tools/list method' do
    let(:params) do
      {
        jsonrpc: '2.0',
        method: 'tools/list',
        id: '1'
      }
    end

    def post_list_tools
      post api('/mcp', user, oauth_access_token: access_token), params: params
    end

    it 'returns success' do
      post_list_tools

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['jsonrpc']).to eq(params[:jsonrpc])
      expect(json_response['id']).to eq(params[:id])
      expect(json_response.keys).to include('result')
    end

    it 'returns tools' do
      post_list_tools

      expect(json_response['result']['tools']).to be_present
    end

    it 'registers and surfaces every MCP tool defined in the codebase', :eager_load, :aggregate_failures do
      defined_tools = Mcp::Tools::Base::BaseService.descendants
        .reject { |klass| klass.superclass == Mcp::Tools::Base::BaseService }

      expect(defined_tools).not_to be_empty, 'No MCP tool services were discovered'

      surfaced_tools = Mcp::Tools::Manager.new.list_tools.values.map(&:class)

      unregistered = defined_tools - surfaced_tools

      expect(unregistered).to be_empty,
        "Tool services defined but not registered in Mcp::Tools::Manager: #{unregistered.map(&:name).join(', ')}"
    end

    it 'locks each tool to its publicly-contracted annotations', :aggregate_failures do
      stub_licensed_features(security_dashboard: true, security_scan_profiles: true)

      post api('/mcp', user, oauth_access_token: access_token),
        params: params,
        headers: { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => 'all' }

      expected_annotations = {
        # write, non-destructive
        'add_branch' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'save_merge_request' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'fork_repository' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'link_work_items' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'save_merge_request_review' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'save_note' => { 'title' => 'Add comment', 'readOnlyHint' => false, 'destructiveHint' => false,
                         'idempotentHint' => false, 'openWorldHint' => false },
        'save_project' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'save_work_item' => { 'readOnlyHint' => false, 'destructiveHint' => false },
        'send_duo_session_input' => { 'title' => 'Send input to Duo session', 'readOnlyHint' => false,
                                      'destructiveHint' => false, 'idempotentHint' => false, 'openWorldHint' => true },
        'start_duo_session' => { 'title' => 'Start Duo session', 'readOnlyHint' => false, 'destructiveHint' => true,
                                 'idempotentHint' => false, 'openWorldHint' => true },
        'attach_scan_profile' => { 'title' => 'Attach security scan profile', 'destructiveHint' => false,
                                   'readOnlyHint' => false, 'idempotentHint' => true, 'openWorldHint' => false },
        'save_vulnerability' => { 'title' => 'Update vulnerability', 'readOnlyHint' => false,
                                  'destructiveHint' => false, 'idempotentHint' => false, 'openWorldHint' => false },
        # write, destructive
        'accept_merge_request' => { 'readOnlyHint' => false, 'destructiveHint' => true },
        'add_commit' => { 'readOnlyHint' => false, 'destructiveHint' => true },
        'save_pipeline' => { 'readOnlyHint' => false, 'destructiveHint' => true },
        # read-only
        'get_artifact_file' => { 'readOnlyHint' => true },
        'get_commit' => { 'readOnlyHint' => true },
        'get_duo_session' => { 'title' => 'Get Duo session', 'readOnlyHint' => true, 'idempotentHint' => true,
                               'openWorldHint' => false },
        'get_job' => { 'readOnlyHint' => true },
        'get_mcp_server_version' => { 'title' => 'Get MCP server version', 'readOnlyHint' => true,
                                      'idempotentHint' => true, 'openWorldHint' => false },
        'get_merge_request' => { 'readOnlyHint' => true },
        'get_pages_content' => { 'readOnlyHint' => true },
        'get_pipeline' => { 'readOnlyHint' => true },
        'get_project' => { 'title' => 'Get project', 'readOnlyHint' => true, 'idempotentHint' => true,
                           'openWorldHint' => false },
        'get_repository_file' => { 'readOnlyHint' => true },
        'get_saved_view_work_items' => { 'readOnlyHint' => true },
        'get_user' => { 'title' => 'Get user', 'readOnlyHint' => true, 'idempotentHint' => true,
                        'openWorldHint' => false },
        'get_vulnerability' => { 'title' => 'Get vulnerability', 'readOnlyHint' => true, 'idempotentHint' => true,
                                 'openWorldHint' => false },
        'get_work_item' => { 'readOnlyHint' => true },
        'get_work_item_types' => { 'readOnlyHint' => true },
        'list_branches' => { 'readOnlyHint' => true },
        'list_commits' => { 'readOnlyHint' => true },
        'list_duo_agents_and_flows' => { 'title' => 'List Duo agents and flows', 'readOnlyHint' => true,
                                         'idempotentHint' => true, 'openWorldHint' => false },
        'list_duo_sessions' => { 'title' => 'List Duo sessions', 'readOnlyHint' => true, 'idempotentHint' => true,
                                 'openWorldHint' => false },
        'list_groups' => { 'title' => 'List groups', 'readOnlyHint' => true, 'idempotentHint' => true,
                           'openWorldHint' => false },
        'list_merge_requests' => { 'readOnlyHint' => true },
        'list_project_members' => { 'title' => 'List project members', 'readOnlyHint' => true, 'idempotentHint' => true,
                                    'openWorldHint' => false },
        'list_pipelines' => { 'readOnlyHint' => true },
        'list_projects' => { 'title' => 'List projects', 'readOnlyHint' => true, 'idempotentHint' => true,
                             'openWorldHint' => false },
        'list_releases' => { 'readOnlyHint' => true },
        'list_repository_tree' => { 'readOnlyHint' => true },
        'list_tags' => { 'readOnlyHint' => true },
        'list_todos' => { 'title' => 'List to-do items', 'readOnlyHint' => true, 'idempotentHint' => true,
                          'openWorldHint' => false },
        'list_vulnerabilities' => { 'title' => 'List vulnerabilities', 'readOnlyHint' => true, 'idempotentHint' => true,
                                    'openWorldHint' => false },
        'list_work_items' => { 'readOnlyHint' => true },
        'search' => { 'title' => 'Search GitLab', 'readOnlyHint' => true, 'idempotentHint' => true,
                      'openWorldHint' => false },
        'search_labels' => { 'title' => 'Search labels', 'readOnlyHint' => true, 'idempotentHint' => true,
                             'openWorldHint' => false },
        'semantic_search' => { 'title' => 'Semantic search', 'readOnlyHint' => true, 'idempotentHint' => true,
                               'openWorldHint' => false },
        'list_wiki_pages' => { 'title' => 'List wiki pages', 'readOnlyHint' => true, 'idempotentHint' => true,
                               'openWorldHint' => false }
      }

      actual_annotations = json_response['result']['tools'].to_h { |tool| [tool['name'], tool['annotations']] }

      expect(actual_annotations).to eq(expected_annotations)
    end

    context 'with the code_security tools' do
      let(:vulnerability_tools) { %w[get_vulnerability list_vulnerabilities save_vulnerability] }
      let(:security_tools) { [*vulnerability_tools, 'attach_scan_profile'] }

      named_tools = %w[get_vulnerability list_vulnerabilities save_vulnerability attach_scan_profile].join(',')

      where(:header, :value) do
        'X-Gitlab-Enabled-Mcp-Server-Toolsets' | 'code_security'
        'X-Gitlab-Enabled-Mcp-Server-Toolsets' | 'all'
        'X-Gitlab-Enabled-Mcp-Server-Tools'    | named_tools
      end

      with_them do
        def listed_tool_names
          post api('/mcp', user, oauth_access_token: access_token), params: params, headers: { header => value }
          json_response['result']['tools'].pluck('name')
        end

        it 'lists the tools when the license includes them' do
          stub_licensed_features(security_dashboard: true, security_scan_profiles: true)

          expect(listed_tool_names).to include(*security_tools)
        end

        it 'does not list a tool when the license does not include its feature', :aggregate_failures do
          stub_licensed_features(security_dashboard: false, security_scan_profiles: true)

          names = listed_tool_names

          expect(names).to include('attach_scan_profile')
          expect(names).not_to include(*vulnerability_tools)
        end
      end
    end

    context 'with the duo_agent_platform toolset' do
      let(:dap_tools) do
        %w[get_duo_session list_duo_agents_and_flows list_duo_sessions send_duo_session_input start_duo_session]
      end

      where(:toolsets_header) { [nil, 'duo_agent_platform', 'all'] }

      with_them do
        let(:headers) { toolsets_header ? { 'X-Gitlab-Enabled-Mcp-Server-Toolsets' => toolsets_header } : {} }

        def listed_tool_names
          post api('/mcp', user, oauth_access_token: access_token), params: params, headers: headers
          json_response['result']['tools'].pluck('name')
        end

        it 'lists the tools when Duo Agent Platform is available for the user' do
          expect(listed_tool_names).to include(*dap_tools)
        end

        it 'does not list the tools when Duo Agent Platform is not available for the user' do
          stub_application_setting(duo_features_enabled: false, lock_duo_features_enabled: true)

          expect(listed_tool_names).not_to include(*dap_tools)
        end
      end
    end

    context 'when tool rules govern the caller' do
      let_it_be(:governing_group) { create(:group, developers: user) }

      let(:governed_tool) { 'get_pipeline' }
      let(:listed_control_tool) { 'search_labels' }

      before do
        user.user_preference.update!(duo_default_namespace_id: governing_group.id)
        stub_feature_flags(duo_mcp_server_governance_rule_enforcement: governing_group)
      end

      def listed_tools
        post_list_tools

        json_response['result']['tools']
      end

      context 'when a tool is denied' do
        before do
          create(:ai_tool_rule, namespace: governing_group, tool_name: governed_tool, local_access: :deny)
        end

        it 'leaves it out of the advertised toolset', :aggregate_failures do
          names = listed_tools.pluck('name')

          expect(names).not_to include(governed_tool)
          expect(names).to include(listed_control_tool)
        end
      end

      context 'when a tool resolves to ask' do
        before do
          create(:ai_tool_rule, namespace: governing_group, tool_name: governed_tool, local_access: :ask)
        end

        it 'advertises it with the interaction annotation alongside its toolset', :aggregate_failures do
          tools = listed_tools
          entry = tools.find { |tool| tool['name'] == governed_tool }
          control = tools.find { |tool| tool['name'] == listed_control_tool }

          expect(entry['_meta']).to eq({ 'com.gitlab/toolset' => 'ci', 'anthropic/requiresUserInteraction' => true })
          expect(control['_meta']).to eq({ 'com.gitlab/toolset' => 'core' })
        end
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
