# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Fetching a single custom field', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:guest) { create(:user, guest_of: group) }

  let_it_be(:text_field) { create(:custom_field, namespace: group, field_type: 'text') }

  let(:query) do
    <<~QUERY
    query($id: IssuablesCustomFieldID!) {
      customField(id: $id) {
        id
        name
      }
    }
    QUERY
  end

  before do
    stub_licensed_features(custom_fields: true)
  end

  it 'returns custom field with the given ID' do
    post_graphql(query, current_user: guest, variables: { id: text_field.to_global_id.to_s })

    expect(response).to have_gitlab_http_status(:ok)

    expect(graphql_data_at(:customField)).to match(
      a_hash_including(
        'id' => text_field.to_global_id.to_s,
        'name' => text_field.name
      )
    )
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_custom_field do
    let(:user) { guest }
    let(:boundary_object) { group }
    let(:request) do
      post_graphql(query, token: { personal_access_token: pat }, variables: { id: text_field.to_global_id.to_s })
    end
  end

  context 'when querying under a group' do
    let(:query) do
      <<~QUERY
      query($id: IssuablesCustomFieldID!) {
        group(fullPath: "#{group.full_path}") {
          customField(id: $id) {
            id
            name
          }
        }
      }
      QUERY
    end

    it 'returns custom field with the given ID' do
      post_graphql(query, current_user: guest, variables: { id: text_field.to_global_id.to_s })

      expect(response).to have_gitlab_http_status(:ok)

      expect(graphql_data_at(:group, :customField)).to match(
        a_hash_including(
          'id' => text_field.to_global_id.to_s,
          'name' => text_field.name
        )
      )
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_custom_field] do
      let(:user) { guest }
      let(:boundary_object) { group }
      let(:request) do
        post_graphql(query, token: { personal_access_token: pat }, variables: { id: text_field.to_global_id.to_s })
      end
    end

    it_behaves_like 'denying a granular token that only authorizes the parent of a field', :read_group do
      let(:user) { guest }
      let(:boundary_object) { group }
      let(:request) do
        post_graphql(query, token: { personal_access_token: pat }, variables: { id: text_field.to_global_id.to_s })
      end

      let(:parent_data_path) { %i[group] }
      let(:field_data_path) { %i[group custom_field] }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      [:read_group, :read_custom_field] do
      let(:user) { guest }
      let(:boundary_object) { group }
      let(:request) do
        post_graphql(query, token: { personal_access_token: pat }, variables: { id: text_field.to_global_id.to_s })
      end

      let(:skipped_data_path) { %i[group custom_field id] }
    end

    context 'when the custom field belongs to a group the token is not scoped to' do
      let_it_be(:other_group) { create(:group, :private, guests: guest) }
      let_it_be(:other_field) { create(:custom_field, namespace: other_group, field_type: 'text') }

      it 'does not return the custom field', :aggregate_failures do
        pat = create(:granular_pat, user: guest, boundary: ::Authz::Boundary.for(group),
          permissions: %w[read_group read_work_item])

        post_graphql(query, token: { personal_access_token: pat }, variables: { id: other_field.to_global_id.to_s })

        expect(graphql_data_at(:group)).to be_present
        expect(graphql_data_at(:group, :custom_field)).to be_nil
      end
    end
  end

  context 'when feature is not available' do
    before do
      stub_licensed_features(custom_fields: false)
    end

    it 'returns an empty result' do
      post_graphql(query, current_user: guest, variables: { id: text_field.to_global_id.to_s })

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_data_at(:customField)).to be_blank
    end
  end
end
