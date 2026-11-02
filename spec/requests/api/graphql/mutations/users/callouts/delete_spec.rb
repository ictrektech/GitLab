# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Delete a user callout', feature_category: :navigation do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:other_user) { create(:user) }

  let(:feature_name) { ::Users::Callout.feature_names.each_key.first }

  let(:input) do
    {
      'featureName' => feature_name
    }
  end

  let(:mutation) { graphql_mutation(:userCalloutDelete, input) }
  let(:mutation_response) { graphql_mutation_response(:userCalloutDelete) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', :dismiss_ui_notification do
    let(:user) { current_user }
    let(:boundary_object) { :user }
    let(:mutation) { graphql_mutation(:userCalloutDelete, input, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'when the user has dismissed the callout' do
    let!(:callout) { create(:callout, user: current_user, feature_name: feature_name) }
    let!(:other_user_callout) { create(:callout, user: other_user, feature_name: feature_name) }

    it 'deletes only the current user callout' do
      expect { post_graphql_mutation(mutation, current_user: current_user) }
        .to change { Users::Callout.count }.by(-1)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['userCallout']['featureName']).to eq(feature_name.upcase)
      expect(Users::Callout.exists?(callout.id)).to be(false)
      expect(Users::Callout.exists?(other_user_callout.id)).to be(true)
    end
  end

  context 'when the user has not dismissed the callout' do
    it 'returns no callout and no errors' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['userCallout']).to be_nil
    end
  end

  context 'when the feature name is unknown' do
    let(:feature_name) { 'unknown_feature' }

    it 'returns no callout and no errors' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['userCallout']).to be_nil
    end
  end
end
