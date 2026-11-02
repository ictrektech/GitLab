# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/doorkeeper/applications/_granular_scopes.html.haml', feature_category: :system_access do
  let(:group) { build_stubbed(:group, path: 'acme') }
  let(:project_namespace) do
    build_stubbed(:project_namespace, project: nil, parent: group, name: 'Widgets', path: 'widgets',
      visibility_level: Gitlab::VisibilityLevel::PRIVATE)
  end

  let(:scopes) do
    [
      build_stubbed(:granular_scope, access: :selected_memberships, namespace: project_namespace,
        permissions: %w[read_member_role unknown_permission]),
      build_stubbed(:granular_scope, access: :user, namespace: nil, permissions: ['execute_mcp_tool']),
      build_stubbed(:granular_scope, access: :selected_memberships, namespace: group,
        permissions: ['read_member_role']),
      build_stubbed(:granular_scope, access: :selected_memberships, namespace: nil, permissions: ['read_member_role'])
    ]
  end

  before do
    render partial: 'shared/doorkeeper/applications/granular_scopes', locals: { scopes: scopes }
  end

  it 'lists namespace scopes by path, then the user scope' do
    headings = Nokogiri::HTML(rendered).css('[data-testid="granular-scope-heading"]').map { |node| node.text.squish }

    expect(headings).to eq([
      'Only specific groups or projects I have access to',
      'acme Group',
      'acme/widgets Project',
      'User permissions'
    ])
  end

  it 'lists each permission with its description when one is known', :aggregate_failures do
    expect(rendered).to have_css('li',
      text: 'execute_mcp_tool (Grants the ability to execute tools through the MCP server)')
    expect(rendered).to have_css('li', exact_text: 'unknown_permission')
  end
end
