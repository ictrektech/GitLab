# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating a work item saved view', feature_category: :portfolio_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, developer_of: group) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_work_item_saved_view do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:mutation) do
      graphql_mutation(
        :workItemSavedViewCreate,
        {
          namespace_path: project.full_path,
          name: 'Project saved view',
          filters: { state: 'opened' },
          display_settings: {},
          sort: 'CREATED_ASC'
        },
        'errors'
      )
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_work_item_saved_view do
    let(:user) { current_user }
    let(:boundary_object) { group }
    let(:mutation) do
      graphql_mutation(
        :workItemSavedViewCreate,
        {
          namespace_path: group.full_path,
          name: 'Group saved view',
          filters: { state: 'opened' },
          display_settings: {},
          sort: 'CREATED_ASC'
        },
        'errors'
      )
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'with relative date filters' do
    let(:filters) do
      { relative_date_filters: { created_after: { amount: -7, unit: :DAY }, due_before: { amount: 2, unit: :WEEK } } }
    end

    let(:mutation) do
      graphql_mutation(
        :workItemSavedViewCreate,
        {
          namespace_path: project.full_path,
          name: 'Recently created',
          filters: filters,
          display_settings: {},
          sort: 'CREATED_ASC'
        },
        'savedView { filters } errors'
      )
    end

    it 'stores and returns the relative values, so the saved view stays relative' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_mutation_response(:work_item_saved_view_create)['savedView']['filters']).to include(
        'relativeDateFilters' => {
          'createdAfter' => { 'amount' => -7, 'unit' => 'DAY' },
          'dueBefore' => { 'amount' => 2, 'unit' => 'WEEK' }
        }
      )
      expect(WorkItems::SavedViews::SavedView.last.filter_data).to include(
        'relative_date_filters' => {
          'created_after' => { 'amount' => -7, 'unit' => 'DAY' },
          'due_before' => { 'amount' => 2, 'unit' => 'WEEK' }
        }
      )
    end

    context 'with the matching absolute filter as well' do
      let(:filters) do
        { created_after: 1.day.ago.iso8601, relative_date_filters: { created_after: { amount: -7, unit: :DAY } } }
      end

      it 'returns an error and does not create the saved view' do
        expect { post_graphql_mutation(mutation, current_user: current_user) }
          .not_to change { WorkItems::SavedViews::SavedView.count }

        expect(graphql_errors).to contain_exactly(
          hash_including(
            'message' => 'Only one of `createdAfter` or `relativeDateFilters.createdAfter` can be provided.'
          )
        )
      end
    end
  end
end
