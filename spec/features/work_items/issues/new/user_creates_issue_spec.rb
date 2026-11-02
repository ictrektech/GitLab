# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "User creates issue", :js, feature_category: :team_planning do
  include DropzoneHelper
  include ListboxHelpers
  include RichTextEditorHelpers

  let_it_be(:project, freeze: false) { create(:project_empty_repo, :public) }
  let_it_be(:user, freeze: false) { create(:user) }

  context "when unauthenticated" do
    before do
      sign_out(:user)
    end

    it "redirects to signin then back to new issue after signin" do
      visit new_project_issue_path(project)

      expect(page).to have_current_path new_user_session_path, ignore_query: true

      gitlab_sign_in(create(:user))

      expect(page).to have_current_path new_project_work_item_path(project), ignore_query: true
    end
  end

  context "when signed in as guest" do
    before do
      project.add_guest(user)
      sign_in(user)
    end

    context 'available metadata' do
      it 'allows guest to set issue metadata' do
        visit(new_project_issue_path(project))

        expect(page).to have_content("Title")
          .and have_content("Description")
          .and have_content("Type")
          .and have_content("Assignee")
          .and have_content("Labels")
          .and have_content("Milestone")
          .and have_content("Dates")
          .and have_unchecked_field(
            "Turn on confidentiality: Limit visibility to project members with at least the Planner role."
          )
      end
    end

    context "when previewing" do
      it "previews content" do
        visit(new_project_issue_path(project))

        click_button("Preview")

        expect(page).to have_text("Nothing to preview.")

        click_button("Continue editing")
        fill_in("Description", with: "Bug fixed :smile:")
        click_button("Preview")

        expect(page).to have_text("Bug fixed 😄")
        expect(page).not_to have_field("Description")

        click_button("Continue editing")
        fill_in("Description", with: "/confidential")
        click_button("Preview")

        expect(page).to have_content('Makes this item confidential.')
      end
    end

    context "with labels" do
      let(:label_titles) { %w[bug feature enhancement] }

      before do
        label_titles.each do |title|
          create(:label, project: project, title: title)
        end
        visit(new_project_issue_path(project))
      end

      it "creates issue" do
        issue_title = "500 error on profile"

        fill_in("Title", with: issue_title)
        within_testid('work-item-labels') do
          click_button _('Edit')
          select_listbox_item label_titles.first
          send_keys(:escape)
        end
        click_button("Create issue")

        expect(page).to have_content(issue_title)
                    .and have_content(user.name)
                    .and have_content(project.name)
                    .and have_content(label_titles.first)
      end
    end

    context 'with due date' do
      it 'saves with due date' do
        visit(new_project_issue_path(project))

        date = Date.current.at_beginning_of_month

        fill_in 'Title', with: 'bug 345'
        fill_in 'Description', with: 'bug description'
        within_testid 'work-item-due-dates' do
          click_button 'Edit'
          find_field('Due').click
        end
        click_button date.day
        click_button 'Apply'
        click_button 'Create issue'

        expect(page).to have_text date.to_fs(:medium)
      end
    end

    context 'dropzone upload file' do
      before do
        visit new_project_issue_path(project)
      end

      it 'uploads file when dragging into textarea' do
        dropzone_file Rails.root.join('spec/fixtures/banana_sample.gif')

        expect(page).to have_field('Description', with: /banana_sample/)
      end

      it "doesn't add double newline to end of a single attachment markdown" do
        dropzone_file Rails.root.join('spec/fixtures/banana_sample.gif')

        expect(page.find_field("Description").value).not_to match(/\n\n$/)
      end

      it "cancels a file upload correctly", :capybara_ignore_server_errors do
        slow_requests do
          dropzone_file([Rails.root.join('spec/fixtures/dk.png')], 0, false)

          within_testid 'markdown-field' do
            click_button 'Cancel'

            expect(page).to have_button('Attach a file or image')
            expect(page).not_to have_button('Cancel')
            expect(page).not_to have_selector('.uploading-progress-container', visible: :visible)
          end
        end
      end
    end

    context 'form filled by URL parameters', :use_null_store_as_repository_cache do
      let(:project) { create(:project, :public, :repository) }

      before do
        project.repository.create_file(
          user,
          '.gitlab/issue_templates/bug.md',
          'this is a test "bug" template',
          message: 'added issue template',
          branch_name: 'master')

        visit new_project_issue_path(project, issuable_template: 'bug')
      end

      it 'fills in template' do
        expect(page).to have_button('bug')
      end
    end

    context 'form create handles issue creation by default' do
      let_it_be(:project, freeze: false) { create(:project) }

      before do
        visit new_project_issue_path(project)
      end

      it 'pre-fills the issue type dropdown with issue type' do
        expect(page).to have_select 'Type', selected: 'Issue'
      end
    end

    context 'form create handles incident creation' do
      let_it_be(:project, freeze: false) { create(:project) }

      before do
        visit new_project_issue_path(project, { issuable_template: 'incident', issue: { issue_type: 'incident' } })
      end

      it 'does not pre-fill the issue type dropdown with incident type' do
        expect(page).to have_select 'Type', selected: 'Issue'
      end
    end

    context 'suggestions' do
      it 'displays list of related issues', :aggregate_failures do
        issue = create(:issue, project: project)
        create(:issue, project: project, title: 'test issue')

        visit new_project_issue_path(project)

        fill_in 'Title', with: issue.title

        # Wait on the result item (rendered only after the debounced query resolves)
        # before the panel title, which is present-but-hidden until then.
        expect(page).to have_css('.suggestion-item', text: issue.title, count: 1)
        expect(page).to have_text('Similar items')
      end
    end

    it 'clears local storage after creating a new issue' do
      2.times do
        visit new_project_issue_path(project)

        expect(page).to have_field('Title', with: '')
        expect(page).to have_field('Description', with: '')

        fill_in 'Title', with: 'bug 345'
        fill_in 'Description', with: 'bug description'

        click_button 'Create issue'
        expect(page).to have_content('bug 345')
      end
    end

    it 'clears local storage after cancelling a new issue creation' do
      2.times do
        visit new_project_issue_path(project)

        expect(page).to have_field('Title', with: '')
        expect(page).to have_field('Description', with: '')

        fill_in 'Title', with: 'bug 345'
        fill_in 'Description', with: 'bug description'

        click_button 'Cancel'
        click_button 'Discard changes'
      end
    end
  end

  context 'when signed in as reporter' do
    let_it_be(:project, freeze: false) { create(:project) }

    before_all do
      project.add_reporter(user)
    end

    before do
      sign_in(user)
    end

    context 'form create handles incident creation' do
      before do
        visit new_project_issue_path(project, { issuable_template: 'incident', issue: { issue_type: 'incident' } })
      end

      it 'pre-fills the issue type dropdown with incident type' do
        expect(page).to have_select 'Type', selected: 'Incident'
        expect(page).to have_css('[data-testid="work-item-milestone"]')
        expect(page).not_to have_css('[data-testid="work-item-parent"]')
        expect(page).not_to have_css('[data-testid="work-item-weight"]')
      end
    end
  end

  context 'when signed in as a maintainer' do
    let_it_be(:project, freeze: false) { create(:project) }

    before_all do
      project.add_maintainer(user)
    end

    before do
      sign_in(user)
      visit(new_project_issue_path(project))
    end

    it_behaves_like 'rich text editor - autocomplete'
    it_behaves_like 'rich text editor - media'

    it_behaves_like 'embedded views (GLQL)'

    it 'creates an issue with a description written in the rich text editor', feature_category: :markdown do
      fill_in 'Title', with: 'Rich text issue'
      switch_to_content_editor
      type_in_content_editor '**bold** text'
      wait_until_hidden_field_is_updated(/\*\*bold\*\* text/)
      click_button 'Create issue'

      within_testid('work-item-description') do
        expect(page).to have_css('strong', text: 'bold')
      end
    end

    describe 'rich text editor placeholders', feature_category: :markdown do
      let(:placeholder_selector) { '[data-testid="content-editor-placeholder"]' }

      before do
        find('textarea').set('Server: %{gitlab_server}')
        switch_to_content_editor
      end

      it 'displays the placeholder syntax in a tooltip on hover' do
        page.within content_editor_testid do
          find(placeholder_selector, text: Gitlab.config.gitlab.host).hover
        end

        expect(page).to have_css('[role="tooltip"]', text: '%{gitlab_server}')
      end

      it 'displays the placeholder syntax in a tooltip only while the placeholder is selected' do
        page.within content_editor_testid do
          find(placeholder_selector).click
        end

        find_button('Switch to plain text editing').hover
        type_in_content_editor :right

        expect(page).to have_no_css('[role="tooltip"]', text: '%{gitlab_server}')

        type_in_content_editor :left

        expect(page).to have_css('[role="tooltip"]', text: '%{gitlab_server}')
      end
    end
  end

  context "when signed in as user with special characters in their name" do
    let(:user_special) { create(:user, name: "Jon O'Shea") }

    before do
      project.add_developer(user_special)
      sign_in(user_special)

      visit(new_project_issue_path(project))
    end

    it "escapes user names with an apostrophe when clicking 'Assign to me'" do
      click_button 'assign yourself'

      expect(page).to have_content(user_special.name)
    end
  end
end
