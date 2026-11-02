# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Security::AttachScanProfileTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:hidden_project) { create(:project, :hidden) }
  let_it_be(:group) { create(:group) }

  let(:project_ids) { [project.to_global_id.to_s] }
  let(:params) do
    {
      security_scan_profile_id: 'gid://gitlab/Security::ScanProfile/1',
      project_ids: project_ids,
      group_ids: [group.to_global_id.to_s]
    }
  end

  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }

  it 'passes the containers the governance lookup resolves', :aggregate_failures do
    input = tool.build_variables[:input]

    expect(input[:projectIds]).to eq([project.to_global_id.to_s])
    expect(input[:groupIds]).to eq([group.to_global_id.to_s])
  end

  context 'with a project the governance lookup skips' do
    let(:project_ids) { [hidden_project.to_global_id.to_s] }

    it 'refuses it' do
      expect { tool.build_variables }.to raise_error(Mcp::Tools::Concerns::ResourceFinder::ResourceNotFoundError)
    end
  end

  context 'with a Global ID of another class' do
    let(:project_ids) { [group.to_global_id.to_s] }

    it 'refuses it' do
      expect { tool.build_variables }.to raise_error(Mcp::Tools::Concerns::ResourceFinder::ResourceNotFoundError)
    end
  end

  context 'with a Global ID of a class that does not exist' do
    let(:project_ids) { ['gid://gitlab/NotAModel/1'] }

    it 'refuses it' do
      expect { tool.build_variables }.to raise_error(Mcp::Tools::Concerns::ResourceFinder::ResourceNotFoundError)
    end
  end

  context 'with a project that does not exist' do
    let(:project_ids) { ["gid://gitlab/Project/#{non_existing_record_id}"] }

    it 'refuses it' do
      expect { tool.build_variables }.to raise_error(Mcp::Tools::Concerns::ResourceFinder::ResourceNotFoundError)
    end
  end
end
