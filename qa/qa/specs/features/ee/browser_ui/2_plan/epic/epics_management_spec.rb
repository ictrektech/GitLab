# frozen_string_literal: true

module QA
  # Add :smoke back once proven reliable
  RSpec.describe 'Plan', feature_category: :portfolio_management do
    describe 'Epics Management' do
      let(:group) { create(:group, name: "group-to-test-epics-#{SecureRandom.hex(4)}") }

      before do
        Flow::Login.sign_in
      end

      it 'creates an epic' do
        epic_title = 'Epic created via GUI'

        EE::Resource::WorkItemEpic.fabricate_via_browser_ui! do |epic|
          epic.group = group
          epic.title = epic_title
        end

        expect(page).to have_content(epic_title)
      end

      it 'creates a confidential epic' do
        epic_title = 'Confidential epic created via GUI'

        EE::Resource::WorkItemEpic.fabricate_via_browser_ui! do |epic|
          epic.group = group
          epic.title = epic_title
          epic.confidential = true
        end

        expect(page).to have_content(epic_title)
        expect(page).to have_css('[data-testid="confidential-badge-text"]', text: 'Confidential')
      end

      context 'when resources created via API' do
        let(:issue) { create_issue_resource }
        let(:epic) { create(:work_item_epic, group: issue.project.group, title: 'Work Item Epic created via API') }

        context 'when visit epic first' do
          before do
            epic.visit!
          end

          it 'adds/removes issue to/from epic' do
            EE::Page::Group::WorkItem::Epic::Show.perform do |show|
              show.add_child_issue_to_epic(issue)

              expect(show).to have_child_issue_item

              show.remove_child_issue_from_epic(issue)

              expect(show).to have_no_child_issue_item
            end
          end
        end

        def create_issue_resource
          project = create(:project, :private, name: 'project-for-issues', description: 'project for adding issues')

          create(:issue, project: project)
        end
      end
    end
  end
end
