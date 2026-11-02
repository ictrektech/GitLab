# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Projects::ListProjectsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }

  let(:service) { described_class.new(name: 'list_projects') }

  before do
    service.set_cred(current_user: user)
  end

  describe '#execute' do
    # TODO: https://gitlab.com/gitlab-org/gitlab/-/work_items/502245
    it_behaves_like 'an MCP tool that avoids N+1 queries', threshold: 4 do
      let(:arguments) { {} }

      before_all do
        create(:project, guests: user, group: create(:group, parent: create(:group)))
      end

      def create_additional_records
        2.times { create(:project, guests: user, group: create(:group, parent: create(:group))) }
      end
    end
  end
end
