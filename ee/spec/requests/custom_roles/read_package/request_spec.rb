# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User with read_package custom role', feature_category: :package_registry do
  include ApiHelpers

  let_it_be(:project) { create(:project, :private, :in_group) }
  let_it_be(:group) { project.group }
  let_it_be(:user) { create(:user) }
  let_it_be(:role) { create(:member_role, :guest, namespace: group, read_package: true) }
  let_it_be(:package) { create(:generic_package, project: project) }

  before do
    stub_licensed_features(custom_roles: true)
    stub_feature_flags(allow_guest_plus_roles_to_pull_packages: false)
  end

  shared_examples 'reading packages via the custom role' do
    it 'lists the project packages', :aggregate_failures do
      get api("/projects/#{project.id}/packages", user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(package.id)
    end

    it 'shows a single package' do
      get api("/projects/#{project.id}/packages/#{package.id}", user)

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'when the user is a project member' do
    before_all do
      create(:project_member, :guest, member_role: role, user: user, project: project)
    end

    it_behaves_like 'reading packages via the custom role'
  end

  context 'when the user is a group member' do
    before_all do
      create(:group_member, :guest, member_role: role, user: user, source: group)
    end

    it_behaves_like 'reading packages via the custom role'
  end

  context 'when the user is a guest without the custom permission' do
    let_it_be(:guest) { create(:user, guest_of: project) }

    it 'denies listing packages' do
      get api("/projects/#{project.id}/packages", guest)

      expect(response).to have_gitlab_http_status(:forbidden)
    end
  end
end
