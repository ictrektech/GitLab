# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Files > User deletes or replaces files', :js, feature_category: :source_code_management do
  let(:commit_message) { 'New commit message' }

  # Create user first to ensure namespace is properly set up
  let_it_be(:user) do
    user = create(:user)
    # Explicitly create and verify namespace
    create(:namespace, owner: user, path: user.username)
    user.reload # Ensure user has the namespace loaded
    user
  end

  let_it_be(:user2) { create(:user) }

  let_it_be(:project) { create(:project, :repository, name: 'Another Project', path: 'another-project') }

  let_it_be(:project_tree_path_root_ref) { project_tree_path(project, project.repository.root_ref) }
  let_it_be(:project_non_default_branch_tree_path) do
    project_tree_path(project, 'non-default-branch')
  end

  def navigate_to_feature_1_file(path)
    visit(path)

    within_testid('file-tree-table') { click_link('encoding') }
    within_testid('file-tree-table') { click_link('feature-1.txt') }

    expect(page).to have_content('feature-1.txt')
  end

  before do
    create :path_lock, path: 'encoding/feature-1.txt', user: user2, project: project
    sign_in(user)
  end

  context 'when a user does not have write access' do
    before_all do
      project.add_reporter(user)
      project.repository.add_branch(user, 'non-default-branch', 'master')
    end

    context 'when a file is locked' do
      it 'does not allow to delete a file from a default branch' do
        navigate_to_feature_1_file(project_tree_path_root_ref)

        click_button 'File actions'

        expect(page).to have_button('Delete', disabled: true)
      end

      it 'does not allow to replace a file from a default branch' do
        navigate_to_feature_1_file(project_tree_path_root_ref)

        click_button 'File actions'

        expect(page).to have_button('Replace', disabled: true)
      end

      it 'deletes a file in a forked project from non-default branch', :js, :sidekiq_might_not_need_inline do
        # Create fork in advance to avoid issues
        Projects::ForkService.new(project, user, {}).execute
        navigate_to_feature_1_file(project_non_default_branch_tree_path)

        click_button 'File actions'
        click_on('Delete')

        fill_in(:commit_message, with: commit_message)
        click_button('Commit changes')

        fork = user.fork_of(project.reload)

        expect(page).to have_current_path(project_new_merge_request_path(fork), ignore_query: true)
        expect(page).to have_content(commit_message)
      end
    end
  end
end
