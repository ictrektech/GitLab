# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unsubscribing from a work item saved view', feature_category: :portfolio_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user, developer_of: group) }

  let_it_be(:project_saved_view) do
    create(:saved_view, namespace: project.project_namespace, author: current_user)
  end

  let_it_be(:group_saved_view) do
    create(:saved_view, namespace: group, author: current_user)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :unsubscribe_work_item_saved_view do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:mutation) do
      graphql_mutation(
        :workItemSavedViewUnsubscribe,
        { id: project_saved_view.to_global_id.to_s },
        'savedView { id }'
      )
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :unsubscribe_work_item_saved_view do
    let(:user) { current_user }
    let(:boundary_object) { group }
    let(:mutation) do
      graphql_mutation(
        :workItemSavedViewUnsubscribe,
        { id: group_saved_view.to_global_id.to_s },
        'savedView { id }'
      )
    end

    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  describe 'savedView in the payload' do
    let_it_be(:private_group) { create(:group, :private, developers: current_user) }
    let_it_be(:private_saved_view) { create(:saved_view, namespace: private_group, author: current_user) }

    let(:pat) do
      create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(private_group),
        permissions: permissions)
    end

    let(:mutation) do
      graphql_mutation(:workItemSavedViewUnsubscribe, { id: private_saved_view.to_global_id.to_s }, 'savedView { id }')
    end

    let(:saved_view_payload) { graphql_mutation_response(:work_item_saved_view_unsubscribe)['savedView'] }

    before do
      create(:user_saved_view, saved_view: private_saved_view, user: current_user)

      post_graphql_mutation(mutation, token: { personal_access_token: pat })
    end

    context 'when the token can also read saved views' do
      let(:permissions) { %i[subscribe_work_item_saved_view read_work_item_saved_view] }

      it 'returns the saved view' do
        expect(saved_view_payload).to eq('id' => private_saved_view.to_global_id.to_s)
      end
    end

    context 'when the token can only unsubscribe' do
      let(:permissions) { :subscribe_work_item_saved_view }

      it 'returns no saved view' do
        expect(saved_view_payload).to be_nil
      end
    end
  end
end
