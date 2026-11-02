# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::MergeRequests::ListMergeRequestsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }

  let(:service) { described_class.new(name: 'list_merge_requests') }

  before do
    service.set_cred(current_user: user)
  end

  describe '#execute' do
    it_behaves_like 'an MCP tool that avoids N+1 queries' do
      let(:arguments) { { group_id: group.full_path } }

      before_all do
        create(:merge_request, source_project: create(:project, :public, group: group))
      end

      def create_additional_records
        2.times do
          subgroup = create(:group, :public, parent: group)
          create(:merge_request, source_project: create(:project, :public, group: subgroup))
        end
      end
    end
  end
end
