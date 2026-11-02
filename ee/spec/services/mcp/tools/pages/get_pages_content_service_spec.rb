# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Pages::GetPagesContentService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :private, group: group, developers: [user]) }

  let_it_be(:deployment) do
    archive = Tempfile.new(['pages', '.zip'])
    Zip::OutputStream.open(archive.path) do |zip|
      zip.put_next_entry('public/index.html')
      zip.write("Members only\n")
    end

    build(:pages_deployment, project: project).tap do |pages_deployment|
      pages_deployment.file = UploadedFile.new(archive.path, filename: 'pages.zip')
      pages_deployment.file_sha256 = Digest::SHA256.file(archive.path).hexdigest
      pages_deployment.file_count = 1
      pages_deployment.save!
    end
  end

  let(:site_url) { "http://#{group.path}.example.com/#{project.path}/" }

  before do
    stub_pages_setting(enabled: true, host: 'example.com', url: 'http://example.com', access_control: true)
  end

  def execute
    service = described_class.new(name: 'get_pages_content', version: '0.1.0')
    access_token = build_stubbed(:personal_access_token, user: user)
    service.set_cred(current_user: user, access_token: access_token)
    service.execute(params: { name: 'get_pages_content', arguments: { url: site_url } })
  end

  it 'serves the site to a member who needs no new SSO session' do
    expect(execute[:structuredContent][:content]).to eq("Members only\n")
  end

  context 'when group SAML SSO requires the member to sign in again' do
    before do
      allow(::Gitlab::Auth::GroupSaml::SsoEnforcer).to receive(:access_restricted?).and_return(true)
    end

    it 'answers as a missing site, like the Pages access check', :aggregate_failures do
      result = execute

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to eq("Tool execution failed: #{described_class::NOT_FOUND}")
    end
  end
end
