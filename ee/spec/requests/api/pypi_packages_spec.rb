# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::PypiPackages, feature_category: :package_registry do
  include WorkhorseHelpers
  include PackagesManagerApiSpecHelpers
  include HttpBasicAuthHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group, freeze: false) { create(:group, maintainers: user) }
  let_it_be(:project, freeze: false) { create(:project, group: group) }
  let_it_be(:personal_access_token) { create(:personal_access_token, user: user) }
  let_it_be(:package_name) { 'Dummy-Package' }
  let_it_be(:package) { create(:pypi_package, project: project, name: package_name, version: '1.0.0') }

  let(:file_sha256) { package.package_files.first.file_sha256 }
  let(:headers) { basic_auth_header(user.username, personal_access_token.token) }
  let(:snowplow_gitlab_standard_context) do
    { project: project, namespace: group, property: 'i_package_pypi_user', user: user }
  end

  subject(:download) { get api(url), headers: headers }

  shared_examples 'allowing auditor to download' do
    context 'when group/project is private' do
      let(:headers) { user_basic_auth_header(create(:auditor)) }

      before do
        target.update_column(:visibility_level, ::Gitlab::VisibilityLevel.const_get(:PRIVATE, false))
      end

      it_behaves_like 'returning response status', :success
    end
  end

  describe 'GET /api/v4/groups/:id/-/packages/pypi/files/:sha256/*file_identifier' do
    let(:url) { "/groups/#{group.id}/-/packages/pypi/files/#{file_sha256}/#{package_name}-1.0.0.tar.gz" }

    it_behaves_like 'applying ip restriction for group'
    it_behaves_like 'allowing auditor to download' do
      let(:target) { group }
    end
  end

  describe 'GET /api/v4/projects/:id/packages/pypi/files/:sha256/*file_identifier' do
    let(:url) { "/projects/#{project.id}/packages/pypi/files/#{file_sha256}/#{package_name}-1.0.0.tar.gz" }

    it_behaves_like 'applying ip restriction for group'
    it_behaves_like 'allowing auditor to download' do
      let(:target) { project }
    end
  end
end
