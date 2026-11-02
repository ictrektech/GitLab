# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Files > User deletes files', :js, feature_category: :source_code_management do
  let(:commit_message) { 'New commit message' }

  let_it_be(:protected_branch) { 'protected-branch' }

  let_it_be(:project) { create(:project, :repository, name: 'Shop') }

  let_it_be_with_reload(:project3) do
    create(:project, :repository, name: 'Test project with protected branch', path: 'protected-branch')
  end

  let_it_be(:project_tree_path_root_ref) { project_tree_path(project, project.repository.root_ref) }

  let_it_be(:project3_protected_branch_tree_path_root_ref) do
    project_tree_path(project3, 'protected-branch', project3.repository.root_ref)
  end

  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  context 'when an user has write access' do
    before_all do
      project.add_maintainer(user)
    end

    before do
      visit(project_tree_path_root_ref)
      wait_for_requests
    end

    it 'deletes the file', :js do
      within_testid('file-tree-table') { click_link('.gitignore') }

      expect(page).to have_content('.gitignore')

      click_button 'File actions'
      click_on('Delete')
      fill_in(:commit_message, with: commit_message, visible: true)
      click_button('Commit changes')

      expect(page).to have_current_path_ignoring_trailing_slash(project_tree_path(project, 'master'))
      expect(page).not_to have_content('.gitignore')
      expect(page).to have_content(commit_message)
    end
  end

  context 'with protected branch' do
    before_all do
      project3.add_developer(user)
      project3.repository.add_branch(user, protected_branch, 'master')
      create(:protected_branch, project: project3, name: protected_branch)
    end

    it 'shows patch branch and option to create MR', :freeze_time do
      visit(project3_protected_branch_tree_path_root_ref)
      wait_for_requests

      within_testid('file-tree-table') { click_link('.gitignore') }

      expect(page).to have_content('.gitignore')

      click_button 'File actions'
      click_on('Delete')

      epoch = Time.zone.now.strftime('%s%L').last(5)
      expect(page).to have_checked_field _('Create a merge request for this change')
      expect(find_field('branch_name').value).to eq "#{user.username}-protected-branch-patch-#{epoch}"

      fill_in(:commit_message, with: commit_message, visible: true)
      click_button('Commit changes')

      expect(page).to have_current_path(project_new_merge_request_path(project3), ignore_query: true)
      expect(page).to have_content(commit_message)
    end
  end
end
