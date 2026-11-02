# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Path Locks', :js, feature_category: :source_code_management do
  include Spec::Support::Helpers::ModalHelpers

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:project) { create(:project, :repository, namespace: user.namespace) }
  let(:tree_path) { project_tree_path(project, project.repository.root_ref) }

  before do
    project.add_maintainer(user)
    project.add_developer(other_user)
    sign_in(user)

    visit tree_path

    wait_for_requests
  end

  # The file and directory lock flows are covered by the frontend integration
  # specs in ee/spec/frontend/integration/repository/path_locks_tree_spec.js
  # and ee/spec/frontend/integration/repository/path_locks_blob_spec.js.
  it 'managing of lock list' do
    create :path_lock, path: 'encoding', user: user, project: project

    click_link "Locked files"

    within '.js-path-locks' do
      expect(page).to have_content('encoding')
    end

    click_link "Unlock"

    accept_gl_confirm('Are you sure you want to unlock encoding?')

    expect(page).not_to have_content('encoding')
  end
end
