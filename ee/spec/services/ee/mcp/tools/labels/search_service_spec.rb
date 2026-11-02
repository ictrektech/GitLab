# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Labels::SearchService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }

  let(:service) { described_class.new(name: 'search_labels') }

  before do
    service.set_cred(current_user: user)
  end

  describe '#execute' do
    # TODO: https://gitlab.com/gitlab-org/gitlab/-/work_items/635535
    it_behaves_like 'an MCP tool that avoids N+1 queries', threshold: 4 do
      let(:arguments) { { full_path: group.full_path, is_project: false } }

      before_all do
        create(:group_label, group: group)
      end

      def create_additional_records
        2.times { create(:group_label, group: create(:group, parent: group)) }
      end
    end
  end
end
