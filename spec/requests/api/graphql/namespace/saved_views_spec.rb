# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Namespace.savedViews', feature_category: :planning_views do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:user) { create(:user, developer_of: group) }
  let_it_be(:group_saved_view) { create(:saved_view, namespace: group, author: user) }
  let_it_be(:project_saved_view) { create(:saved_view, namespace: project.project_namespace, author: user) }

  let(:saved_views_field) { query_graphql_field(:saved_views, {}, 'nodes { id name }') }
  let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

  describe 'granular PAT authorization' do
    context 'when querying a group through the namespace field' do
      let(:boundary_object) { group }
      let(:query) { graphql_query_for(:namespace, { full_path: group.full_path }, saved_views_field) }

      it_behaves_like 'authorizing granular token permissions for GraphQL',
        [:read_namespace, :read_work_item_saved_view]

      it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_namespace do
        let(:parent_data_path) { %i[namespace] }
        let(:field_data_path) { %i[namespace saved_views] }
      end
    end

    context 'when querying a project namespace through the namespace field' do
      let(:boundary_object) { project }
      let(:query) { graphql_query_for(:namespace, { full_path: project.full_path }, saved_views_field) }

      it_behaves_like 'authorizing granular token permissions for GraphQL',
        [:read_namespace, :read_work_item_saved_view]

      it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_namespace do
        let(:parent_data_path) { %i[namespace] }
        let(:field_data_path) { %i[namespace saved_views] }
      end
    end

    context 'when querying through the group field' do
      let(:boundary_object) { group }
      let(:query) { graphql_query_for(:group, { full_path: group.full_path }, saved_views_field) }

      it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_work_item_saved_view]

      it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_group do
        let(:parent_data_path) { %i[group] }
        let(:field_data_path) { %i[group saved_views] }
      end
    end
  end
end
