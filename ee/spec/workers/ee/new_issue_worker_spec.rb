# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NewIssueWorker, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }

  describe '#perform' do
    let(:worker) { described_class.new }

    context 'when project bot it logs audit events' do
      let_it_be(:project_bot) { create(:user, :project_bot, email: "bot@example.com", maintainer_of: project) }

      include_examples 'audit event logging' do
        let(:issue) { create(:issue, title: "My issue", project: project, author: project_bot) }
        let(:operation) { worker.perform(issue.id, project_bot.id) }
        let(:event_type) { 'issue_created_by_project_bot' }
        let(:fail_condition!) { allow_any_instance_of(User).to receive(:project_bot?).and_return(false) } # rubocop:disable RSpec/AnyInstanceOf
        let(:attributes) do
          {
            author_id: project_bot.id,
            entity_id: issue.project.id,
            entity_type: 'Project',
            details: {
              author_name: project_bot.name,
              event_name: "issue_created_by_project_bot",
              target_id: issue.id,
              target_type: 'Issue',
              target_details: {
                iid: issue.iid,
                id: issue.id
              }.to_s,
              author_class: project_bot.class.name,
              custom_message: "Created issue #{issue.title}"
            }
          }
        end
      end
    end

    context 'when project bot creates a group-level epic it logs audit events' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project_bot) { create(:user, :project_bot, email: "bot@example.com", maintainer_of: group) }

      include_examples 'audit event logging' do
        let(:licensed_features_to_stub) { { epics: true } }
        let(:work_item) { create(:work_item, :epic, title: "My epic", namespace: group, author: project_bot) }
        let(:operation) { worker.perform(work_item.id, project_bot.id, 'WorkItem') }
        let(:event_type) { 'epic_created_by_project_bot' }
        let(:fail_condition!) { allow_any_instance_of(User).to receive(:project_bot?).and_return(false) } # rubocop:disable RSpec/AnyInstanceOf -- User is loaded from DB
        let(:attributes) do
          {
            author_id: project_bot.id,
            entity_id: group.id,
            entity_type: 'Group',
            details: {
              author_name: project_bot.name,
              event_name: "epic_created_by_project_bot",
              target_id: work_item.id,
              target_type: 'WorkItem',
              target_details: {
                iid: work_item.iid,
                id: work_item.id
              }.to_s,
              author_class: project_bot.class.name,
              custom_message: "Created epic #{work_item.title}"
            }
          }
        end
      end
    end

    context 'when project bot creates a ticket it logs audit events' do
      let_it_be(:project_bot) { create(:user, :project_bot, email: "bot@example.com", maintainer_of: project) }

      include_examples 'audit event logging' do
        let(:ticket) { create(:issue, :ticket, title: "My ticket", project: project, author: project_bot) }
        let(:operation) { worker.perform(ticket.id, project_bot.id) }
        let(:event_type) { 'ticket_created_by_project_bot' }
        let(:fail_condition!) { allow_any_instance_of(User).to receive(:project_bot?).and_return(false) } # rubocop:disable RSpec/AnyInstanceOf -- User is loaded from DB
        let(:attributes) do
          {
            author_id: project_bot.id,
            entity_id: ticket.project.id,
            entity_type: 'Project',
            details: {
              author_name: project_bot.name,
              event_name: "ticket_created_by_project_bot",
              target_id: ticket.id,
              target_type: 'Issue',
              target_details: {
                iid: ticket.iid,
                id: ticket.id
              }.to_s,
              author_class: project_bot.class.name,
              custom_message: "Created ticket #{ticket.title}"
            }
          }
        end
      end
    end

    context 'when project bot creates a group-level work item it logs audit events' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project_bot) { create(:user, :project_bot, email: "group_bot@example.com", maintainer_of: group) }
      let_it_be(:epic) { create(:work_item, :epic, namespace: group, title: "My epic", author: project_bot) }

      include_examples 'audit event logging' do
        let(:licensed_features_to_stub) { { epics: true } }
        let(:operation) { worker.perform(epic.id, project_bot.id, 'WorkItem') }
        let(:event_type) { 'epic_created_by_project_bot' }
        let(:fail_condition!) { allow_any_instance_of(User).to receive(:project_bot?).and_return(false) } # rubocop:disable RSpec/AnyInstanceOf -- User is loaded from DB
        let(:attributes) do
          {
            author_id: project_bot.id,
            entity_id: group.id,
            entity_type: 'Group',
            details: {
              author_name: project_bot.name,
              event_name: "epic_created_by_project_bot",
              target_id: epic.id,
              target_type: 'WorkItem',
              target_details: {
                iid: epic.iid,
                id: epic.id
              }.to_s,
              author_class: project_bot.class.name,
              custom_message: "Created epic #{epic.title}"
            }
          }
        end
      end
    end
  end
end
