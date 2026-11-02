# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Merge request AI overview', :js, feature_category: :code_review_workflow do
  let(:user) { create(:user, :with_namespace) }
  let(:group) { create(:group) }
  let(:project) { create(:project, :repository, group: group) }
  let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  before do
    project.add_maintainer(user)
    sign_in(user)
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(mr_ai_overview: false)
    end

    it 'offers no toggle' do
      visit project_merge_request_path(project, merge_request)

      click_button 'More actions'

      expect(page).not_to have_button 'Try the new overview'
    end
  end

  context 'when the feature flag is enabled for the current user' do
    before do
      stub_feature_flags(mr_ai_overview: user)
    end

    it 'opts in from the overflow menu and replaces the Overview tab' do
      visit project_merge_request_path(project, merge_request)

      expect(page).to have_selector('.merge-request-overview')

      click_button 'More actions'
      click_button 'Try the new overview'

      expect(page).to have_selector('.ai-overview-body')
      expect(page).not_to have_selector('.merge-request-overview')
    end

    context 'when the user has opted in' do
      before do
        # set_cookie would load the homepage, whose background user counts request can still be writing
        # when the example creates records. A page without JavaScript sends no such request.
        visit '/robots.txt'
        set_cookie('mr_ai_overview_enabled', 'true')
      end

      it 'renders the merge readiness rows' do
        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="readiness-row"]', count: 4)
      end

      it 'gives a merge check without a row of its own a row while it blocks' do
        merge_request.update!(title: "Draft: #{merge_request.title}")

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="readiness-row"]', count: 5)

        # The detail sits in a tooltip on the row's label.
        find_by_testid('readiness-row-label', text: 'Draft').hover

        expect(page).to have_content('Merge request must not be draft.')
      end

      it 'says a merged merge request is merged, rather than scoring it for readiness' do
        merge_request.mark_as_merged!

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_content('This merge request has been merged.')
        expect(page).not_to have_selector('[data-testid="readiness-row"]')
      end

      it 'lists the reviewers with what each has done so far' do
        reviewer = create(:user, name: 'Priya Nair', developer_of: project)
        merge_request.update!(reviewers: [reviewer])

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="reviewer-row"]', count: 1)
        expect(page).to have_content('Priya Nair')
        expect(page).to have_content('Awaiting review')
        expect(page).to have_content('0 of 1 approved')
      end

      it 'names the current user as the blocker when their approval is what the merge waits on' do
        stub_licensed_features(merge_request_approvers: true)
        create(:approval_project_rule, :any_approver_rule, project: project, approvals_required: 1)
        merge_request.update!(reviewers: [user])

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_content('Your review is the blocker')
      end

      it 'renders the description as markdown' do
        merge_request.update!(description: 'Adds **rate limiting**.')

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_content("Created by #{merge_request.author.name}")

        within_testid('description-content') do
          expect(page).to have_css('strong', text: 'rate limiting')
        end
      end

      it 'lists the labels and milestone', :aggregate_failures do
        label = create(:label, project: project, title: 'backend')
        milestone = create(:milestone, project: project, title: '19.5')
        merge_request.update!(labels: [label], milestone: milestone)

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_content('backend')
        expect(page).to have_link('19.5')
      end

      it 'lists the comment threads, linking a diff thread to the Changes tab', :aggregate_failures do
        create(:diff_note_on_merge_request, noteable: merge_request, project: project, note: 'Rename this.')
        create(:discussion_note_on_merge_request, noteable: merge_request, project: project, note: 'Add a changelog.')
        create(:note_on_merge_request, :system, noteable: merge_request, project: project, note: 'changed the title')

        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('[data-testid="conversation-row"]', count: 2)
        expect(page).to have_content('Add a changelog.')
        expect(page).not_to have_content('changed the title')
        expect(find_by_testid('conversation-location')[:href]).to include(
          "#{diffs_project_merge_request_path(project, merge_request)}?file_path="
        )
      end

      it 'resolves a thread from its row' do
        note = create(:discussion_note_on_merge_request, noteable: merge_request, project: project)

        visit project_merge_request_path(project, merge_request)

        within_testid('conversations-filter') { click_button 'All' }
        within_testid('conversation-row') do
          # The thread actions only show while the note is hovered or focused.
          find_by_testid('conversation-opening').hover
          click_button 'Resolve'
        end

        expect(page).to have_selector('[data-testid="conversation-state"][aria-label="Resolved"]')
        expect(note.reload).to be_resolved
      end

      it 'leaves the other tabs working' do
        visit project_merge_request_path(project, merge_request)

        expect(page).to have_selector('.ai-overview-body')

        click_link 'Changes'

        expect(page).to have_selector('diff-file')
      end

      it 'still boots the sidebar bundle, which owns controls outside the sidebar' do
        visit project_merge_request_path(project, merge_request)

        click_button 'More actions'

        # The unmounted placeholder reads "Lock merge request"; the mounted form reads "Lock discussion".
        expect(page).to have_button 'Lock discussion'
      end

      it 'mounts once when arriving on another tab and switching back' do
        visit commits_project_merge_request_path(project, merge_request)

        within('.merge-request-tabs') { click_link 'Overview' }

        expect(page).to have_selector('.ai-overview-body', count: 1)
      end

      it 'opts back out from the overflow menu' do
        visit project_merge_request_path(project, merge_request)

        click_button 'More actions'
        click_button 'Switch to the classic overview'

        expect(page).to have_selector('.merge-request-overview')
        expect(page).not_to have_selector('.ai-overview-body')
      end
    end
  end
end
