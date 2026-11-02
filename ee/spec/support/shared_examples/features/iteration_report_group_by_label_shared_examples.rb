# frozen_string_literal: true

RSpec.shared_examples 'iteration report group by label' do
  before do
    select 'Label', from: 'Group by'

    # The burndown and burnup charts above the issues card render asynchronously
    # and shift the layout, which can move the dropdown button out from under a
    # pending click. Retry until the labels list opens.
    wait_for('labels dropdown to open') do
      click_button 'Label' unless has_testid?('labels-list', wait: 0)
      has_testid?('labels-list', wait: 1)
    rescue Capybara::ElementNotFound
      false
    end

    within_testid('labels-list') { click_link label1.title }
    send_keys(:escape)

    find_button 'Collapse issues'
  end

  it 'groups by label', :aggregate_failures do
    page.within('#content-body') do
      expect(page).to have_button('Collapse issues')
      expect(page).to have_css('.gl-label', text: label1.title)
      expect(page).to have_css('.gl-badge', text: 2)

      expect(page).to have_content(issue.title)
      expect(page).to have_content(assigned_issue.title)
      expect(page).to have_no_content(closed_issue.title)
      expect(page).to have_no_content(other_iteration_issue.title)
    end
  end

  it 'shows ungrouped issues when `Group by: None` is selected again', :aggregate_failures do
    page.within('#content-body') do
      select 'None', from: 'Group by'

      expect(page).to have_no_button('Collapse issues')
      expect(page).to have_no_css('.gl-label', text: label1.title)
      expect(page).to have_no_css('.gl-badge', text: 2)

      expect(page).to have_content(issue.title)
      expect(page).to have_content(assigned_issue.title)
      expect(page).to have_content(closed_issue.title)
      expect(page).to have_no_content(other_iteration_issue.title)
    end
  end

  it 'shows ungrouped issues when label `x` is clicked to remove it', :aggregate_failures do
    within_testid('iteration-issues-section') do
      click_button 'Remove label'
    end

    page.within('#content-body') do
      expect(page).to have_no_button('Collapse issues')
      expect(page).to have_no_css('.gl-label', text: label1.title)
      expect(page).to have_no_css('.gl-badge', text: 2)

      expect(page).to have_content(issue.title)
      expect(page).to have_content(assigned_issue.title)
      expect(page).to have_content(closed_issue.title)
      expect(page).to have_no_content(other_iteration_issue.title)
    end
  end
end
