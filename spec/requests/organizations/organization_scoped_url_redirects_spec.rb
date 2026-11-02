# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization-scoped URL redirects', feature_category: :organization do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:group) { create(:group, :public, organization: organization) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:user) { create(:user, :with_namespace, organization: organization) }

  before do
    sign_in(user)
  end

  describe 'GET requests' do
    it 'redirects a group URL to the canonical one' do
      get "/o/#{organization.path}/#{group.full_path}"

      expect(response).to have_gitlab_http_status(:found)
      expect(response).to redirect_to("/#{group.full_path}")
    end

    it 'redirects a group sub-resource URL, keeping the query string' do
      get "/o/#{organization.path}/groups/#{group.full_path}/-/activity?limit=5"

      expect(response).to redirect_to("/groups/#{group.full_path}/-/activity?limit=5")
    end

    it 'redirects a project URL to the canonical one' do
      get "/o/#{organization.path}/#{project.full_path}/-/issues"

      expect(response).to redirect_to("/#{project.full_path}/-/issues")
    end

    it 'redirects a user profile URL to the canonical one' do
      get "/o/#{organization.path}/#{user.username}"

      expect(response).to redirect_to("/#{user.username}")
    end

    it 'redirects a user sub-page URL to the canonical one' do
      get "/o/#{organization.path}/users/#{user.username}/activity"

      expect(response).to redirect_to("/users/#{user.username}/activity")
    end

    it 'redirects under any organization, since the canonical URL does not depend on it' do
      get "/o/#{other_organization.path}/#{group.full_path}"

      expect(response).to redirect_to("/#{group.full_path}")
    end

    it 'does not redirect a reserved first segment' do
      get "/o/#{organization.path}/-/does-not-exist"

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'does not redirect a path that starts with an encoded slash' do
      get "/o/#{organization.path}/%2F%2Fevil.example.com"

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'never redirects to another host' do
      get "/o/#{organization.path}/groups/%2F%2Fevil.example.com"

      expect(response).to redirect_to("/groups/evil.example.com")
    end
  end

  # Forms and XHR requests from a page rendered before a deploy still target
  # the scoped URLs. 307 repeats them, method and body included.
  describe 'other requests' do
    it 'redirects a project request with 307' do
      post "/o/#{organization.path}/#{project.full_path}/-/preview_markdown", params: { text: 'hello' }

      expect(response).to have_gitlab_http_status(:temporary_redirect)
      expect(response.location).to end_with("/#{project.full_path}/-/preview_markdown")
    end

    it 'redirects a group request with 307' do
      delete "/o/#{organization.path}/groups/#{group.full_path}/-/labels/1"

      expect(response).to have_gitlab_http_status(:temporary_redirect)
      expect(response.location).to end_with("/groups/#{group.full_path}/-/labels/1")
    end

    it 'does not redirect a reserved first segment' do
      expect { post "/o/#{organization.path}/-/does-not-exist" }
        .to raise_error(ActionController::RoutingError)
    end
  end

  # Git starts every operation with GET info/refs and, by default, follows a
  # redirect there and keeps using the redirected URL for the requests that
  # follow (http.followRedirects=initial). The POST itself never crosses it.
  describe 'Git over HTTP' do
    it 'redirects the ref discovery, keeping the service parameter' do
      get "/o/#{organization.path}/#{project.full_path}.git/info/refs?service=git-upload-pack"

      expect(response).to redirect_to("/#{project.full_path}.git/info/refs?service=git-upload-pack")
    end

    it 'redirects a pack request with 307' do
      post "/o/#{organization.path}/#{project.full_path}.git/git-upload-pack"

      expect(response).to have_gitlab_http_status(:temporary_redirect)
      expect(response.location).to end_with("/#{project.full_path}.git/git-upload-pack")
    end
  end

  describe 'pages that stay organization-scoped' do
    it 'still serves the new group page' do
      get "/o/#{organization.path}/groups/new"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'still serves the organization activity page' do
      get "/o/#{organization.path}/-/activity"

      expect(response).to have_gitlab_http_status(:ok)
    end

    # A reserved word alone, without a trailing segment, is the trap the
    # redirect constraint must not fall into. Only a request shows it:
    # recognize_path skips redirect endpoints.
    it 'still serves pages whose path is a single reserved word' do
      get "/o/#{organization.path}/help"
      expect(response).to have_gitlab_http_status(:ok)

      get "/o/#{organization.path}/search"
      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'still serves the organization admin area' do
      owner = create(:user, :organization_owner, organization: organization)
      sign_in(owner)

      get "/o/#{organization.path}/admin"

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'still serves the sign-in page' do
      sign_out(user)

      get "/o/#{organization.path}/users/sign_in"

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  # Nothing writes such a route yet. Renaming the root route is how a
  # prefixed row comes to exist here.
  describe 'a group whose own route path carries the prefix' do
    let_it_be(:prefixed_group, freeze: false) { create(:group, :public, organization: organization) }

    before_all do
      prefixed_group.route.update!(path: "o/#{organization.path}/#{prefixed_group.path}")
    end

    it 'is served, not redirected' do
      get "/o/#{organization.path}/#{prefixed_group.path}"

      expect(response).to have_gitlab_http_status(:ok)
    end
  end
end
