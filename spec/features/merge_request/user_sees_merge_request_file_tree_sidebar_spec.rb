# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request > User sees merge request file tree sidebar', :js, feature_category: :code_review_workflow do
  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let(:user) { project.creator }
  let(:sidebar) { find('.diff-tree-list') }
  let(:sidebar_scroller) { sidebar.find('.vue-recycle-scroller') }

  before do
    sign_in(user)
    visit diffs_project_merge_request_path(project, merge_request)
    wait_for_requests
  end

  it 'sees file tree sidebar' do
    expect(page).to have_selector('[data-testid="file-tree-container"]')
  end

  shared_examples 'last entry clickable' do
    specify do
      # The file browser height is recalculated asynchronously (and debounced
      # twice) as the tree scrolls, so the last row can briefly sit below the
      # fold. Keep scrolling to the bottom until the layout settles and the last
      # entry is actually clickable, rather than sampling `obscured?` once.
      # Rows are links for files and buttons for folders, so match both.
      row = nil
      wait_for('last file tree entry to be clickable') do
        sidebar_scroller.execute_script('this.scrollBy(0,99999)')
        row = find_all('[data-testid="file-tree-container"] nav [data-testid="file-row"]').last
        row && !row.obscured?
      end

      title = row.find('[data-testid=file-row-name-container]')[:title]
      row.click

      expect(page).to have_css('[data-testid="rd-diff-file-header"]', text: title)
    end
  end

  it_behaves_like 'last entry clickable'

  context 'when viewing using file-by-file mode' do
    let(:user) { create(:user, view_diffs_file_by_file: true) }

    it_behaves_like 'last entry clickable'

    context 'when navigating to the next file' do
      before do
        find_by_testid('file-by-file-navigation').click_button('Next')
        wait_for_requests
      end

      it_behaves_like 'last entry clickable'
    end
  end
end
