# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Create a label or backlog board list', feature_category: :planning_views do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:board) { create(:epic_board, group: group) }

  before do
    stub_licensed_features(epics: true)
  end

  it_behaves_like 'board lists create request' do
    let(:mutation_name) { :epic_board_list_create }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_epic_board_list do
    let_it_be(:user) { create(:user, developer_of: group) }

    let(:boundary_object) { group }
    let(:mutation) do
      graphql_mutation(:epic_board_list_create, { board_id: board.to_global_id.to_s, backlog: true })
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end
end
