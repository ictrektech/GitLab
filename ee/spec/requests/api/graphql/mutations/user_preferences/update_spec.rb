# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::UserPreferences::Update, feature_category: :user_profile do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:orbit_mutation_query) do
    <<~GQL
      mutation($input: UserPreferencesUpdateInput!) {
        userPreferencesUpdate(input: $input) {
          userPreferences { orbitSettings }
          errors
        }
      }
    GQL
  end

  def post_orbit_mutation(orbit_settings_value, user: current_user)
    post_graphql(
      orbit_mutation_query,
      current_user: user,
      variables: { input: { orbitSettings: orbit_settings_value } }.to_json
    )
  end

  describe 'effective orbit_settings response', feature_category: :duo_agent_platform do
    let(:all_enabled_settings) do
      {
        'enabled' => true,
        'orbit_agent_enabled' => true,
        'orbit_agentic_chat_enabled' => true,
        'orbit_other_foundational_agents_enabled' => true,
        'orbit_custom_agents_enabled' => true
      }
    end

    before do
      allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).and_return(orbit_on)
    end

    context 'when Orbit in Duo is off' do
      let(:orbit_on) { false }

      it 'returns every effective setting as false' do
        post_orbit_mutation({})

        expect(graphql_data.dig('userPreferencesUpdate', 'userPreferences', 'orbitSettings'))
          .to eq(all_enabled_settings.transform_values { false })
      end
    end

    context 'when Orbit in Duo is on' do
      let(:orbit_on) { true }

      it 'returns every effective setting as true by default' do
        post_orbit_mutation({})

        expect(graphql_data.dig('userPreferencesUpdate', 'userPreferences', 'orbitSettings'))
          .to eq(all_enabled_settings)
      end

      it 'ignores a stored enabled value' do
        post_orbit_mutation({ 'enabled' => false })

        expect(graphql_data.dig('userPreferencesUpdate', 'userPreferences', 'orbitSettings'))
          .to eq(all_enabled_settings)
      end
    end
  end

  describe 'issuesSort with a weight sort', :aggregate_failures, feature_category: :team_planning do
    # A fresh user per example, so no preference record is cached from an earlier example.
    let(:user) { create(:user) }

    let(:issues_sort_query) do
      <<~GQL
        mutation($input: UserPreferencesUpdateInput!) {
          userPreferencesUpdate(input: $input) {
            userPreferences { issuesSort }
            errors
          }
        }
      GQL
    end

    where(:sort_value) { %w[WEIGHT_ASC WEIGHT_DESC] }

    with_them do
      it 'saves the sort and returns it' do
        post_graphql(
          issues_sort_query,
          current_user: user,
          variables: { input: { issuesSort: sort_value } }.to_json
        )

        expect(graphql_errors).to be_nil
        expect(graphql_data.dig('userPreferencesUpdate', 'userPreferences', 'issuesSort')).to eq(sort_value)
        expect(UserPreference.find_by(user: user).issues_sort).to eq(sort_value.downcase)
      end

      it 'returns the saved sort when reading the preferences' do
        user.user_preference.update!(issues_sort: sort_value.downcase)

        post_graphql(graphql_query_for(:current_user, {}, 'userPreferences { issuesSort }'), current_user: user)

        expect(graphql_errors).to be_nil
        expect(graphql_data.dig('currentUser', 'userPreferences', 'issuesSort')).to eq(sort_value)
      end
    end
  end

  describe 'orbit_settings validation', feature_category: :duo_agent_platform do
    context 'when orbit_settings has invalid schema' do
      it 'returns validation error' do
        post_orbit_mutation({ 'invalid_key' => 'value' })

        expect(response).to have_gitlab_http_status(:success)
        expect(graphql_data.dig('userPreferencesUpdate', 'errors'))
          .to include('Orbit settings must be a valid json schema')
        expect(graphql_data.dig('userPreferencesUpdate', 'userPreferences')).to be_nil
      end
    end
  end
end
