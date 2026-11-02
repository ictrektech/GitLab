# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'get_pages_content access', feature_category: :mcp_server do
  let_it_be(:owner) { create(:user) }
  let_it_be(:outsider) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:owner_token) { create(:oauth_access_token, user: owner, scopes: [:mcp]) }
  let_it_be(:outsider_token) { create(:oauth_access_token, user: outsider, scopes: [:mcp]) }
  let_it_be(:page_html) { "<html>Team handbook</html>\n" }

  let_it_be(:archive, freeze: false) do
    Tempfile.new(['pages', '.zip']).tap do |zip|
      Zip::OutputStream.open(zip.path) do |out|
        out.put_next_entry('public/index.html')
        out.write(page_html)
      end
    end
  end

  let(:pages_auth_header) do
    {
      Gitlab::Pages::INTERNAL_API_REQUEST_HEADER =>
        JWT.encode({ 'iss' => 'gitlab-pages' }, Gitlab::Pages.secret, 'HS256')
    }
  end

  before do
    stub_application_setting(instance_level_ai_beta_features_enabled: true)
    stub_pages_setting(enabled: true, host: 'example.com', url: 'http://example.com', access_control: true)
    allow(Gitlab::Pages).to receive(:secret).and_return(SecureRandom.random_bytes(Gitlab::Pages::SECRET_LENGTH))
  end

  def deploy_pages(project)
    build(:pages_deployment, project: project).tap do |deployment|
      deployment.file = UploadedFile.new(archive.path, filename: 'pages.zip')
      deployment.file_sha256 = Digest::SHA256.file(archive.path).hexdigest
      deployment.file_count = 1
      deployment.save!
    end
  end

  def get_pages_content(user, token, url)
    post api('/mcp', user, oauth_access_token: token), params: {
      jsonrpc: '2.0',
      method: 'tools/call',
      params: { name: 'get_pages_content', arguments: { url: url } },
      id: '1'
    }

    expect(response).to have_gitlab_http_status(:ok)
    json_response['result']
  end

  context 'when a public project is made private' do
    let_it_be_with_reload(:project) { create(:project, :public, group: group, owners: [owner]) }
    let(:host) { "#{group.path}.example.com" }
    let(:site_url) { "http://#{host}/#{project.path}/" }

    before_all do
      deploy_pages(project)
    end

    before do
      put api("/projects/#{project.id}", owner), params: { visibility: 'private' }
    end

    it 'leaves the Pages setting on "Everyone with access"', :aggregate_failures do
      expect(project.reload).to be_private
      expect(project.project_feature.pages_access_level).to eq(ProjectFeature::ENABLED)
    end

    it 'tells gitlab-pages to check access before serving the site' do
      get api('/internal/pages'), headers: pages_auth_header, params: { host: host }

      expect(response).to have_gitlab_http_status(:ok)
      lookup_path = json_response['lookup_paths'].find { |path| path['project_id'] == project.id }
      expect(lookup_path['access_control']).to be(true)
    end

    it 'passes the access check gitlab-pages makes for a member and fails it for a non-member' do
      get api("/projects/#{project.id}/pages_access", owner)
      expect(response).to have_gitlab_http_status(:ok)

      get api("/projects/#{project.id}/pages_access", outsider)
      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'serves the site to a member through MCP', :aggregate_failures do
      result = get_pages_content(owner, owner_token, site_url)

      expect(result['isError']).to be(false)
      expect(result['structuredContent']['content']).to eq(page_html)
    end

    it 'does not serve the site to a non-member through MCP', :aggregate_failures do
      result = get_pages_content(outsider, outsider_token, site_url)

      expect(result['isError']).to be(true)
      expect(result.to_json).not_to include('Team handbook')
    end
  end

  context 'when a private project publishes its Pages for everyone on a custom domain' do
    let_it_be(:project) { create(:project, :private, group: group, owners: [owner]) }
    let_it_be(:domain) { create(:pages_domain, project: project) }
    let(:site_url) { "https://#{domain.domain}/" }

    before_all do
      deploy_pages(project)
    end

    before do
      put api("/projects/#{project.id}", owner), params: { pages_access_level: 'public' }
    end

    it 'lets gitlab-pages serve the site to everyone' do
      get api('/internal/pages'), headers: pages_auth_header, params: { host: domain.domain }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['lookup_paths'].first['access_control']).to be(false)
    end

    it 'hides the project from a non-member' do
      get api("/projects/#{project.id}", outsider)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'serves the site to a non-member through MCP without naming the project', :aggregate_failures do
      result = get_pages_content(outsider, outsider_token, site_url)
      missing = get_pages_content(outsider, outsider_token, "#{site_url}missing/")

      expect(result['structuredContent']['content']).to eq(page_html)
      expect(result['structuredContent']).not_to have_key('project_id')
      expect(missing['isError']).to be(true)
      expect(missing.to_json).not_to include(project.full_path)
    end
  end
end
