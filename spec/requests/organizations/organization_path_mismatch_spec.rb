# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization-scoped URLs naming a mismatched organization', feature_category: :organization do
  # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- groups outside any explicit organization live here
  let_it_be(:default_organization) { create(:organization, :default) }
  # rubocop:enable Gitlab/RSpec/AvoidCreateDefaultOrganization

  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }

  let_it_be(:group) { create(:group, :public, organization: default_organization) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:scoped_group) { create(:group, :public, organization: organization) }

  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  # The organization segment is dropped before any lookup, so the response
  # never depends on which organization the URL names or whether the group
  # exists or is readable.
  context 'when the URL names an organization the group does not belong to' do
    it 'redirects a group page to the canonical URL' do
      get "/o/#{other_organization.path}/groups/#{group.full_path}"

      expect(response).to redirect_to("/groups/#{group.full_path}")
    end

    it 'redirects a project page to the canonical URL' do
      get "/o/#{other_organization.path}/#{project.full_path}"

      expect(response).to redirect_to("/#{project.full_path}")
    end

    it 'redirects a group in a non-default organization to the canonical URL' do
      get "/o/#{other_organization.path}/groups/#{scoped_group.full_path}"

      expect(response).to redirect_to("/groups/#{scoped_group.full_path}")
    end

    it 'redirects when the named organization does not exist' do
      get "/o/nonexistent-org/groups/#{group.full_path}"

      expect(response).to redirect_to("/groups/#{group.full_path}")
    end

    it 'redirects non-GET requests with 307' do
      post "/o/#{other_organization.path}/groups/#{group.full_path}/-/preview_markdown", params: { text: 'text' }

      expect(response).to have_gitlab_http_status(:temporary_redirect)
      expect(response.location).to end_with("/groups/#{group.full_path}/-/preview_markdown")
    end

    it 'responds like a nonexistent path for a group the user cannot read (security)' do
      private_group = create(:group, :private, organization: default_organization)

      get "/o/#{other_organization.path}/groups/#{private_group.full_path}"
      private_status = response.status

      get "/o/#{other_organization.path}/groups/does-not-exist"

      expect(private_status).to eq(302)
      expect(response).to have_gitlab_http_status(:found)
    end

    it 'redirects anonymous users to the canonical URL, like a nonexistent path' do
      sign_out(user)

      get "/o/#{other_organization.path}/groups/#{group.full_path}"

      expect(response).to redirect_to("/groups/#{group.full_path}")
    end
  end

  context 'when the URL names the organization the group belongs to' do
    it 'redirects to the canonical URL' do
      get "/o/#{organization.path}/groups/#{scoped_group.full_path}"

      expect(response).to redirect_to("/groups/#{scoped_group.full_path}")
    end

    it 'redirects when the prefix differs only in case' do
      get "/o/#{organization.path.upcase}/groups/#{scoped_group.full_path}"

      expect(response).to redirect_to("/groups/#{scoped_group.full_path}")
    end
  end
end
