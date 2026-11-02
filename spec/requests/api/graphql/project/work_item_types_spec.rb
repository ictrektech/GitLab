# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting a list of work item types for a project', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private) }
  let_it_be(:developer) { create(:user, developer_of: project) }

  it_behaves_like 'graphql work item type list request spec' do
    let(:current_user) { developer }
    let(:parent) { project }
  end

  it_behaves_like 'authorizing granular token permissions for work item type list', :read_project do
    let(:user) { developer }
    let(:parent) { project }
  end

  describe 'granular PAT authorization of widget definitions' do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:query) do
      graphql_query_for(:project, { full_path: project.full_path },
        query_nodes(:work_item_types, 'id name widgetDefinitions { type }'))
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_work_item_type] do
      let(:skipped_data_path) { %i[project work_item_types nodes widget_definitions type] }
    end
  end
end
