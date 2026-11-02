# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting a list of work item types for a project EE', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :private) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let(:parent) { project }
  let(:current_user) { developer }

  it_behaves_like 'graphql work item type list request spec', 'with work item types request context EE'

  it_behaves_like 'graphql work item type list request spec EE'

  describe 'granular PAT authorization' do
    let(:user) { developer }
    let(:boundary_object) { project }
    let(:query) do
      graphql_query_for(:project, { full_path: project.full_path },
        query_nodes(:work_item_types, 'id name widgetDefinitions { type }'))
    end

    let(:request) { post_graphql(query, token: { personal_access_token: pat }) }

    before do
      licenses = ::EE::WorkItems::TypesFramework::SystemDefined::WidgetDefinition::WIDGETS_WITH_LICENSE.values
      stub_licensed_features(licenses.index_with(true))
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_project, :read_work_item_type] do
      let(:skipped_data_path) { %i[project work_item_types nodes widget_definitions type] }
    end
  end
end
