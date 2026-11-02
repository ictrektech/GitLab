# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Files > User replaces files', :js, feature_category: :source_code_management do
  include DropzoneHelper

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

    it 'replaces an existed file with a new one' do
      within_testid('file-tree-table') { click_link('.gitignore') }

      expect(page).to have_content('.gitignore')

      click_button 'File actions'
      click_on('Replace')
      find(".upload-dropzone-card").drop(File.join(Rails.root, 'spec', 'fixtures', 'doc_sample.txt'))

      page.within('#modal-replace-blob') do
        fill_in(:commit_message, with: 'Replacement file commit message')
        click_button('Commit changes')
      end

      expect(page).to have_content('Lorem ipsum dolor sit amet')
      expect(page).to have_content('Sed ut perspiciatis unde omnis')
      expect(page).to have_content('Replacement file commit message')
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
      click_on('Replace')

      epoch = Time.zone.now.strftime('%s%L').last(5)
      expect(find_field('branch_name').value).to eq "#{user.username}-protected-branch-patch-#{epoch}"
      find(".upload-dropzone-card").drop(File.join(Rails.root, 'spec', 'fixtures', 'doc_sample.txt'))
      page.within('#modal-replace-blob') do
        fill_in(:commit_message, with: 'Replacement file commit message')
        click_button('Commit changes')
      end

      expect(page).to have_content('Replacement file commit message')

      expect(page).to have_current_path(project_new_merge_request_path(project3), ignore_query: true)

      click_link('Changes')

      expect(page).to have_content('Lorem ipsum dolor sit amet')
      expect(page).to have_content('Sed ut perspiciatis unde omnis')
    end
  end
end
