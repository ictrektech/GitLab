# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Work items bulk editing', :js, feature_category: :planning_views do
  include FilteredSearchHelpers
  include WorkItemsHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:bug_label) { create(:label, project: project, title: 'bug') }
  let_it_be(:feature_label) { create(:label, project: project, title: 'feature') }
  let_it_be(:frontend_label) { create(:label, project: project, title: 'frontend') }
  let_it_be(:wontfix_label) { create(:label, project: project, title: 'wontfix') }
  let_it_be(:issue) { create(:work_item, :issue, project: project, title: "Issue without label") }
  let_it_be(:task) { create(:work_item, :task, project: project, title: "Task without label") }
  let_it_be(:task_2) { create(:work_item, :task, project: project, title: "Task 2") }
  let_it_be(:incident) { create(:incident, project: project, title: "Incident 1") }
  let_it_be(:issue_with_label) do
    create(:work_item, :issue, project: project, title: "Issue with label", labels: [frontend_label])
  end

  let_it_be(:issue_with_multiple_labels) do
    create(:work_item, :issue, project: project, title: "Issue with multiple labels",
      labels: [frontend_label, wontfix_label, feature_label])
  end

  before_all do
    project.add_developer(user)
  end

  before do
    sign_in user
  end

  context 'when user is signed in' do
    context 'when bulk editing labels on project work items' do
      before do
        visit project_work_items_path(project)
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns labels' do
        let(:work_item) { issue }
        let(:work_item_with_label) { issue_with_label }
        let(:work_item_2) { task }
      end

      it_behaves_like 'when user bulk unassigns labels' do
        let(:work_item_with_label) { issue_with_label }
        let(:work_item_with_multiple_labels) { issue_with_multiple_labels }
      end

      it_behaves_like 'when user bulk assigns and unassigns labels simultaneously' do
        let(:work_item) { issue }
        let(:work_item_with_label) { issue_with_label }
      end
    end

    context 'when bulk editing labels on project issues list' do
      before do
        visit project_issues_path(project)
        wait_for_requests
        # clear the type filter as we will also update task
        click_button 'Clear'
        # After clearing, the filtered search activates the last token which can
        # open the suggestion dropdown that overlays other elements. Blur the active
        # element to deactivate the search and dismiss the dropdown.
        page.execute_script('document.activeElement.blur()')
        expect_hidden_suggestions_list
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns labels' do
        let(:work_item) { issue }
        let(:work_item_with_label) { issue_with_label }
      end

      it_behaves_like 'when user bulk assign labels on mixed work item types' do
        let(:work_item) { issue }
        let(:work_item_2) { task }
      end

      it_behaves_like 'when user bulk unassigns labels' do
        let(:work_item_with_label) { issue_with_label }
        let(:work_item_with_multiple_labels) { issue_with_multiple_labels }
      end

      it_behaves_like 'when user bulk assigns and unassigns labels simultaneously' do
        let(:work_item) { issue }
        let(:work_item_with_label) { issue_with_label }
      end
    end

    context 'when bulk editing parent on project issue list' do
      before do
        allow(Gitlab::QueryLimiting).to receive(:threshold).and_return(137)

        visit project_issues_path(project)

        # clear the type filter as we will also update task
        click_button 'Clear'
        page.execute_script('document.activeElement.blur()')
        expect_hidden_suggestions_list
        find('span', text: task.title)
        click_bulk_edit
      end

      it_behaves_like 'when user bulk assigns parent' do
        let(:child_work_item) { task }
        let(:parent_work_item) { issue }
        let(:child_work_item_2) { task_2 }
      end

      context 'when unassigning a parent' do
        before do
          create(:parent_link, work_item_parent: issue, work_item: task)
          create(:parent_link, work_item_parent: issue, work_item: task_2)
          page.refresh

          click_bulk_edit
        end

        it_behaves_like 'when user bulk unassigns parent' do
          let(:child_work_item) { task }
          let(:parent_work_item) { issue }
          let(:child_work_item_2) { task_2 }
        end
      end

      it_behaves_like 'when parent bulk edit shows no available items' do
        let(:incompatible_work_item) { incident }
        let(:incompatible_work_item_1) { issue }
        let(:incompatible_work_item_2) { task }
      end

      it_behaves_like 'when parent bulk edit fetches correct work items' do
        let(:child_work_item) { task }
        let(:parent_work_item) { issue }
        let(:incident_work_item) { incident }
      end
    end
  end
end

# A separate top-level describe, not a context nested in the one above, so this group
# does not inherit the outer `before_all`/`before` (it signs in and authorizes its own
# user and project, and nesting it previously signed in twice per example).
RSpec.describe 'Work items bulk editing when bulk editing issue state, assignee, and milestone ' \
  'from the work items list', :js, feature_category: :planning_views do
  include ListboxHelpers

  let!(:project) { create(:project) }
  let!(:issue)   { create(:issue, project: project) }
  let!(:user)    { create(:user) }

  before do
    project.add_maintainer(user)
    sign_in(user)
  end

  context 'when updating state' do
    it 'sets to closed' do
      visit project_work_items_path(project)

      click_button 'Bulk edit'
      check 'Select all'
      select_from_listbox('Closed', from: 'Select state')

      click_update_issues_button
      expect(page).to have_selector('.issue', count: 0)
    end

    it 'sets to open' do
      create_closed
      visit project_work_items_path(project, state: 'closed')

      click_button 'Bulk edit'
      check 'Select all'
      select_from_listbox('Open', from: 'Select state')

      click_update_issues_button
      expect(page).to have_selector('.issue', count: 0)
    end
  end

  context 'when updating assignee' do
    it 'updates to current user' do
      visit project_work_items_path(project)

      click_button 'Bulk edit'
      check 'Select all'
      click_update_assignee_button
      select_listbox_item(user.username)

      click_update_issues_button

      expect(find('.issue:first-of-type')).to have_link "Assigned to #{user.name}"
    end

    it 'updates to unassigned' do
      create_assigned
      visit project_work_items_path(project)

      expect(find('.issue:first-of-type')).to have_link "Assigned to #{user.name}"

      click_button 'Bulk edit'
      check 'Select all'
      click_update_assignee_button
      select_listbox_item('Unassigned')
      click_update_issues_button

      expect(find('.issue:first-of-type')).not_to have_link "Assigned to #{user.name}"
    end
  end

  context 'when updating milestone' do
    let!(:milestone) { create(:milestone, project: project) }

    it 'updates milestone' do
      visit project_work_items_path(project)

      click_button 'Bulk edit'
      check 'Select all'
      click_update_milestone_button
      select_listbox_item(milestone.title)
      click_update_issues_button

      expect(page.find('.issue')).to have_content milestone.title
    end

    it 'sets to no milestone' do
      create_with_milestone
      visit project_work_items_path(project)

      wait_for_requests

      expect(find('.issue:first-of-type')).to have_text milestone.title

      click_button 'Bulk edit'
      check 'Select all'
      click_update_milestone_button
      select_listbox_item('No milestone')
      click_update_issues_button

      expect(find('.issue:first-of-type')).not_to have_text milestone.title
    end
  end

  describe 'select all issues' do
    let!(:issue_2) { create(:issue, project: project) }

    it 'after selecting all issues, unchecking one issue only unselects that one issue' do
      visit project_work_items_path(project)

      click_button 'Bulk edit'
      check 'Select all'
      uncheck issue.title

      expect(page).to have_unchecked_field 'Select all'
      expect(page).to have_unchecked_field issue.title
      expect(page).to have_checked_field issue_2.title
    end
  end

  def create_closed
    create(:issue, project: project, state: :closed)
  end

  def create_assigned
    create(:issue, project: project, assignees: [user])
  end

  def create_with_milestone
    create(:issue, project: project, milestone: milestone)
  end

  def click_update_assignee_button
    click_button 'Select assignee'
    wait_for_requests
  end

  def click_update_milestone_button
    click_button 'Select milestone'
    wait_for_requests
  end

  def click_update_issues_button
    click_button 'Update selected'
    wait_for_requests
  end
end
