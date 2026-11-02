# frozen_string_literal: true

require "spec_helper"

RSpec.describe "User sorts work items", :js, feature_category: :planning_views do
  include Features::SortingHelpers
  include SortingHelper
  include FilteredSearchHelpers
  include IssueHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project_empty_repo, :public, group: group) }
  let_it_be_with_reload(:issue) { create(:issue, title: 'issue', created_at: Time.zone.now, project: project) }
  let_it_be_with_reload(:task) do
    create(:work_item, :task, title: 'task', created_at: Time.zone.now - 60, project: project)
  end

  let_it_be_with_reload(:incident) do
    create(:incident, title: 'incident', created_at: Time.zone.now - 120, project: project)
  end

  before_all do
    project.add_owner(user)
    project.add_developer(user2)
  end

  before do
    sign_in(user)
  end

  it 'sorts by newest' do
    visit project_work_items_path(project)

    expect(first_issue).to include('issue')
    expect(last_issue).to include('incident')
  end

  it 'sorts by most recently updated' do
    task.updated_at = Time.zone.now
    task.save!
    visit project_work_items_path(project)

    click_button 'Display'
    pajamas_sort_by 'Updated date', from: 'Created date'

    wait_for_requests

    expect(first_issue).to include('task')
  end

  describe 'sorting by dates' do
    before do
      task.update!(due_date: 1.day.from_now)
      issue.update!(due_date: 6.days.from_now)
      incident.update!(start_date: 8.days.from_now)
    end

    it 'sorts by start date' do
      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Start date', from: 'Created date'

      wait_for_requests

      expect(first_issue).to include('incident')
    end

    it 'sorts by due date' do
      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Due date', from: 'Created date'

      wait_for_requests

      expect(first_issue).to include('issue')
    end

    it 'sorts by due date reverse order' do
      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Due date', from: 'Created date'

      click_button _('Sort direction: Descending')

      wait_for_requests

      expect(first_issue).to include('task')
    end

    it 'sorts by due date by excluding nil due dates' do
      task.update!(due_date: nil)

      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Due date', from: 'Created date'

      wait_for_requests

      expect(first_issue).to include('issue')
    end
  end

  describe 'sorting by title' do
    it 'sorts by ascending' do
      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Title', from: 'Created date'

      click_button _('Sort direction: Descending')

      wait_for_requests

      expect(first_issue).to include('incident')
    end

    it 'sorts by descending' do
      visit project_work_items_path(project)

      click_button 'Display'
      pajamas_sort_by 'Title', from: 'Created date'

      wait_for_requests

      expect(first_issue).to include('task')
    end
  end

  describe 'combine filter and sort', :js do
    before do
      issue.assignees << user2
      issue.save!
      task.assignees << user2
      task.save!
    end

    it 'sorts with a filter applied' do
      visit project_work_items_path(project)

      select_tokens 'Assignee', '=', user2.username, submit: true

      click_button 'Display'
      pajamas_sort_by 'Title', from: 'Created date'

      wait_for_requests

      expect(first_issue).to include('task')
      expect(last_issue).to include('issue')
      expect(page).not_to have_content('incident')
    end
  end
end

# A separate top-level describe, not a context nested in the one above, so this group
# does not inherit the outer `before`/`before_all` (it signs in and authorizes its own
# user and project, and nesting it previously signed in twice per example).
RSpec.describe "User sorts work items when sorting by milestone, popularity, and a label-filtered due date",
  :js, feature_category: :planning_views do
  include Features::SortingHelpers
  include SortingHelper
  include IssueHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project_empty_repo, :public, group: group) }
  let_it_be_with_reload(:issue1) { create(:issue, title: 'foo', created_at: Time.zone.now, project: project) }
  let_it_be_with_reload(:issue2) { create(:issue, title: 'bar', created_at: Time.zone.now - 60, project: project) }
  let_it_be_with_reload(:issue3) { create(:issue, title: 'baz', created_at: Time.zone.now - 120, project: project) }
  let_it_be(:newer_due_milestone) { create(:milestone, project: project, due_date: '2013-12-11') }
  let_it_be(:later_due_milestone) { create(:milestone, project: project, due_date: '2013-12-12') }

  before_all do
    project.add_developer(user)
  end

  before do
    create_list(:award_emoji, 2, :upvote, awardable: issue1)
    create_list(:award_emoji, 2, :downvote, awardable: issue2)
    create(:award_emoji, :downvote, awardable: issue1)
    create(:award_emoji, :upvote, awardable: issue2)
    sign_in(user)
  end

  it 'keeps the sort option' do
    visit(project_work_items_path(project))
    expect(page).to have_content(issue1.title)

    click_button 'Display'
    pajamas_sort_by 'Milestone due date', from: 'Created date'
    expect(page).to have_content(issue1.title)

    visit(issues_dashboard_path(assignee_username: user.username))
    visit(project_work_items_path(project))

    click_button 'Display'
    expect(page).to have_button 'Milestone'

    visit(group_work_items_path(group))
    expect(page).to have_content(issue1.title)

    click_button 'Display'
    pajamas_sort_by 'Milestone due date', from: 'Created date'
    expect(page).to have_content(issue1.title)

    visit(issues_dashboard_path(assignee_username: user.username))
    visit(group_work_items_path(group))

    click_button 'Display'
    expect(page).to have_button 'Milestone'
  end

  it 'sorts by popularity' do
    visit(project_work_items_path(project))

    click_button 'Display'
    pajamas_sort_by 'Popularity', from: 'Created date'

    page.within(".issues-list") do
      page.within("li.issue:nth-child(1)") do
        expect(page).to have_content(issue1.title)
      end

      page.within("li.issue:nth-child(2)") do
        expect(page).to have_content(issue2.title)
      end

      page.within("li.issue:nth-child(3)") do
        expect(page).to have_content(issue3.title)
      end
    end
  end

  it 'sorts by milestone' do
    issue1.milestone = newer_due_milestone
    issue1.save!
    issue2.milestone = later_due_milestone
    issue2.save!

    visit project_work_items_path(project, sort: sort_value_milestone)

    expect(first_issue).to include('foo')
    expect(last_issue).to include('baz')
  end

  it 'sorts by least recently due date by excluding nil due dates, with a label filter applied' do
    issue1.update!(due_date: 1.day.from_now)
    issue2.update!(due_date: nil)
    label = create(:label, project: project)
    create(:label_link, label: label, target: issue1)

    visit project_work_items_path(project, label_names: [label.name], sort: sort_value_due_date_later)

    expect(first_issue).to include('foo')
  end
end
