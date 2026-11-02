# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::MavenPackages, feature_category: :package_registry do
  include WorkhorseHelpers
  include HttpBasicAuthHelpers

  include_context 'workhorse headers'

  before do
    stub_feature_flags(maven_problem_details_errors: false)
  end

  let_it_be(:user) { create(:user) }
  let_it_be(:personal_access_token) { create(:personal_access_token, user: user) }
  let_it_be(:group) { create(:group, maintainers: user) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:package) { create(:maven_package, project: project, name: project.full_path) }
  let_it_be(:maven_metadatum) { package.maven_metadatum }
  let_it_be(:package_file) { package.package_files.with_file_name_like('%.xml').first }

  let(:headers) { { 'Private-Token' => personal_access_token.token } }

  describe 'GET /api/v4/groups/:id/-/packages/maven/*path/:file_name' do
    let(:url) { "/groups/#{group.id}/-/packages/maven/#{maven_metadatum.path}/#{package_file.file_name}" }

    subject { get api(url), headers: headers }

    it_behaves_like 'applying ip restriction for group'
  end

  describe 'GET /api/v4/projects/:id/packages/maven/*path/:file_name' do
    let(:url) { "/projects/#{project.id}/packages/maven/#{maven_metadatum.path}/#{package_file.file_name}" }

    subject { get api(url), headers: headers }

    it_behaves_like 'applying ip restriction for group'
  end

  describe 'RFC 9457 problem details' do
    context 'with project-level download and non-existing path' do
      before do
        stub_feature_flags(maven_problem_details_errors: true)
        # Disable request forwarding so the API raises `not_found!('Project')`
        # instead of forwarding the request to Maven Central.
        stub_feature_flags(maven_central_request_forwarding: false)
      end

      subject do
        get api("/projects/#{project.id}/packages/maven/non/existent/path/foo.jar"), headers: headers
      end

      it_behaves_like 'returning RFC 9457 problem details', status: :not_found, detail: '404 Project Not Found'

      context 'when maven_problem_details_errors is disabled' do
        before do
          stub_feature_flags(maven_problem_details_errors: false)
        end

        it_behaves_like 'not returning RFC 9457 problem details', status: :not_found
      end
    end
  end
end
