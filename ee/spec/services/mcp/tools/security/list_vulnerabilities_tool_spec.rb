# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Security::ListVulnerabilitiesTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:hidden_project) { create(:project, :hidden) }

  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }

  context 'with a project the governance lookup resolves' do
    let(:params) { { project_full_path: project.full_path.upcase } }

    it 'queries its canonical path' do
      expect(tool.send(:build_variables_v0_1_0)[:fullPath]).to eq(project.full_path)
    end
  end

  context 'with a project the governance lookup skips' do
    let(:params) { { project_full_path: hidden_project.full_path } }

    it 'answers not found without asking GraphQL', :aggregate_failures do
      expect(GitlabSchema).not_to receive(:execute)

      result = tool.execute

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include('Project not found')
    end
  end
end
