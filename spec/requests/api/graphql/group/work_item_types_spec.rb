# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting a list of work item types for a group', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:developer) { create(:user, developer_of: group) }

  it_behaves_like 'graphql work item type list request spec' do
    let(:current_user) { developer }
    let(:parent) { group }
  end

  it_behaves_like 'authorizing granular token permissions for work item type list', :read_group do
    let(:user) { developer }
    let(:parent) { group }
  end

  describe 'granular PAT authorization of widget definitions' do
    let(:user) { developer }
    let(:boundary_object) { group }
    let(:query) do
      graphql_query_for(:group, { full_path: group.full_path },
        query_nodes(:work_item_types, 'id name widgetDefinitions { type }'))
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_group, :read_work_item_type] do
      let(:skipped_data_path) { %i[group work_item_types nodes widget_definitions type] }
    end
  end
end
