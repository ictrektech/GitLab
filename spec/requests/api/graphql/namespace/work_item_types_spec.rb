# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting a list of work item types for a group', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:namespace) { create(:group, :private) }
  let_it_be(:developer) { create(:user, developer_of: namespace) }

  it_behaves_like 'graphql work item type list request spec' do
    let(:current_user) { developer }
    let(:parent) { namespace }
  end

  describe 'granular PAT authorization' do
    let(:user) { developer }
    let(:boundary_object) { namespace }
    let(:query) do
      graphql_query_for(:namespace, { full_path: namespace.full_path },
        query_nodes(:work_item_types, 'id name widgetDefinitions { type }'))
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_namespace, :read_work_item_type]

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_namespace, :read_work_item_type] do
      let(:skipped_data_path) { %i[namespace work_item_types nodes widget_definitions type] }
    end

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_namespace do
      let(:parent_data_path) { %i[namespace] }
      let(:field_data_path) { %i[namespace work_item_types] }
    end

    context 'when querying a project namespace' do
      let_it_be(:project) { create(:project, :private, group: namespace) }

      let(:boundary_object) { project }
      let(:query) do
        graphql_query_for(:namespace, { full_path: project.full_path },
          query_nodes(:work_item_types, 'id name widgetDefinitions { type }'))
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_namespace, :read_work_item_type]

      it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_namespace do
        let(:parent_data_path) { %i[namespace] }
        let(:field_data_path) { %i[namespace work_item_types] }
      end
    end
  end
end
