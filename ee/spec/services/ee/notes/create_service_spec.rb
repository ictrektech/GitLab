# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notes::CreateService, feature_category: :team_planning do
  context 'note with commands' do
    let(:project) { create(:project) }
    let(:note_params) { opts }

    let_it_be(:user) { create(:user) }

    context 'for issues', feature_category: :team_planning do
      let(:issuable) { create(:issue, project: project, weight: 10) }
      let(:opts) { { noteable_type: 'Issue', noteable_id: issuable.id } }

      it_behaves_like 'issuable quick actions' do
        let(:quick_actions) do
          [
            QuickAction.new(
              action_text: '/weight 5',
              expectation: ->(noteable, can_use_quick_action) {
                expect(noteable.weight == 5).to eq(can_use_quick_action)
              }
            ),
            QuickAction.new(
              action_text: '/clear_weight',
              expectation: ->(noteable, can_use_quick_action) {
                if can_use_quick_action
                  expect(noteable.weight).to be_nil
                else
                  expect(noteable.weight).not_to be_nil
                end
              }
            )
          ]
        end
      end

      context "with assignees quick actions" do
        let(:update_service) { Issues::UpdateService }
        let(:noteable_type) { 'Issue' }

        context "with a single line note" do
          let(:validation_message) { "Assignees total must be less than or equal to 2" }

          let(:note_text) do
            "/assign #{user1.to_reference} #{user2.to_reference} #{user3.to_reference}"
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end

        context "with a multi line note" do
          let(:validation_message) { "Assignees total must be less than or equal to 2" }
          let(:note_text) do
            <<~HEREDOC
                  /assign #{user1.to_reference}
                  /assign #{user2.to_reference}
                  /assign #{user3.to_reference}
            HEREDOC
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end
      end
    end

    context 'for merge_requests', feature_category: :code_review_workflow do
      let(:issuable) { create(:merge_request, project: project, source_project: project) }
      let(:developer) { create(:user) }
      let(:opts) { { noteable_type: 'MergeRequest', noteable_id: issuable.id } }

      it_behaves_like 'issuable quick actions' do
        let(:quick_actions) do
          [
            QuickAction.new(
              before_action: -> {
                project.add_developer(developer)
                issuable.update!(reviewers: [user])
              },

              action_text: "/reassign_reviewer #{developer.to_reference}",
              expectation: ->(issuable, can_use_quick_action) {
                expect(issuable.reviewers == [developer]).to eq(can_use_quick_action)
              }
            )
          ]
        end
      end

      context "with assignees quick actions" do
        let(:update_service) { MergeRequests::UpdateService }
        let(:noteable_type) { 'MergeRequest' }

        context "with a single line note" do
          let(:validation_message) { "Assignees total must be less than or equal to 2" }
          let(:note_text) do
            "/assign #{user1.to_reference} #{user2.to_reference} #{user3.to_reference}"
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end

        context "with a multi line note" do
          let(:validation_message) { "Assignees total must be less than or equal to 2" }
          let(:note_text) do
            <<~HEREDOC
                  /assign #{user1.to_reference}
                  /assign #{user2.to_reference}
                  /assign #{user3.to_reference}
            HEREDOC
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end
      end

      context "with reviewers quick actions" do
        let(:update_service) { MergeRequests::UpdateService }
        let(:noteable_type) { 'MergeRequest' }

        context "with a single line note" do
          let(:validation_message) { "Reviewers total must be less than or equal to 2" }

          let(:note_text) do
            "/assign_reviewer #{user1.to_reference} #{user2.to_reference} #{user3.to_reference}"
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end

        context "with a multi line note" do
          let(:validation_message) { "Reviewers total must be less than or equal to 2" }
          let(:note_text) do
            <<~HEREDOC
              /assign_reviewer #{user1.to_reference}
              /assign_reviewer #{user2.to_reference}
              /assign_reviewer #{user3.to_reference}
            HEREDOC
          end

          it_behaves_like 'does not exceed the issuable size limit'
        end
      end
    end

    context 'for epics', feature_category: :portfolio_management do
      let_it_be(:epic) { create(:epic) }

      let(:opts) { { noteable_type: 'Epic', noteable_id: epic.id, note: "hello" } }

      it 'tracks epic note creation' do
        expect(::Gitlab::UsageDataCounters::EpicActivityUniqueCounter).to receive(:track_epic_note_created_action)
          .with(author: user, namespace: epic.group)

        described_class.new(nil, user, opts).execute
      end
    end

    context 'for group wikis', feature_category: :wiki do
      let_it_be(:group) { create(:group) }
      let_it_be_with_reload(:wiki_page_meta) { create(:wiki_page_meta, :for_wiki_page, container: group) }
      let(:opts) do
        {
          note: 'reply',
          noteable_type: 'WikiPage::Meta',
          noteable_id: wiki_page_meta.id,
          namespace: wiki_page_meta.namespace
        }
      end

      before do
        stub_licensed_features(group_wikis: true)
      end

      it_behaves_like 'internal event tracking' do
        let(:event) { 'create_wiki_page_note' }
        let(:category) { described_class.name }
        let(:project) { nil }
        let(:namespace) { wiki_page_meta.namespace }

        subject(:track_event) { described_class.new(nil, user, opts).execute }
      end

      context 'for a non-first note in a discussion' do
        let_it_be_with_reload(:previous_note) do
          create(:note, noteable: wiki_page_meta, project: nil, namespace: wiki_page_meta.namespace)
        end

        let(:opts) do
          {
            in_reply_to_discussion_id: previous_note.discussion_id,
            note: 'reply',
            noteable_type: 'WikiPage::Meta',
            noteable_id: wiki_page_meta.id,
            namespace: wiki_page_meta.namespace
          }
        end

        it 'creates the note' do
          note = described_class.new(nil, user, opts).execute

          expect(note).to be_valid
        end

        it_behaves_like 'internal event tracking' do
          let(:event) { 'create_wiki_page_reply_note' }
          let(:category) { described_class.name }
          let(:project) { nil }
          let(:namespace) { wiki_page_meta.namespace }

          subject(:track_event) { described_class.new(nil, user, opts).execute }
        end
      end
    end
  end

  context 'when created during a Duo workflow request' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:issue) { create(:issue, project: project) }

    let(:opts) { { note: 'a comment', noteable_type: 'Issue', noteable_id: issue.id } }
    let(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

    subject(:created_note) { described_class.new(project, user, opts).execute }

    around do |example|
      ::Gitlab::ApplicationContext.with_context(duo_workflow_id: workflow.id.to_s) { example.run }
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      stub_ee_application_setting(duo_features_enabled: true)
      allow(user).to receive(:allowed_to_use?).with(:duo_agent_platform, anything).and_return(true)
    end

    it 'records a created link from the workflow to the new note' do
      expect { created_note }.to change { Ai::DuoWorkflows::WorkflowNote.count }.by(1)

      link = Ai::DuoWorkflows::WorkflowNote.order(:id).last
      expect(link).to have_attributes(
        workflow: workflow,
        note_id: created_note.id,
        link_type: 'created'
      )
    end

    it 'records the link before NewNoteWorker is queued' do
      expect(NewNoteWorker).to receive(:perform_async) do |note_id|
        expect(Ai::DuoWorkflows::WorkflowNote.where(workflow: workflow, note_id: note_id)).to exist
      end

      created_note
    end

    context 'when no Duo workflow id is in the request context' do
      around do |example|
        ::Gitlab::ApplicationContext.with_context(duo_workflow_id: nil) { example.run }
      end

      it 'does not record a link' do
        expect { created_note }.not_to change { Ai::DuoWorkflows::WorkflowNote.count }
      end

      context 'when the caller passes the workflow' do
        let(:workflow) { create(:duo_workflows_workflow, project: project, user: create(:user)) }
        let(:opts) { super().merge(workflow: workflow) }

        it 'records a created link before NewNoteWorker is queued', :aggregate_failures do
          expect(NewNoteWorker).to receive(:perform_async) do |note_id|
            expect(Ai::DuoWorkflows::WorkflowNote.where(workflow: workflow, note_id: note_id)).to exist
          end

          expect(created_note).to be_persisted
          expect(Ai::DuoWorkflows::WorkflowNote.sole).to have_attributes(note_id: created_note.id,
            link_type: 'created')
        end
      end
    end

    context 'when the current user is not authorized to update the workflow' do
      let(:workflow) { create(:duo_workflows_workflow, project: project, user: create(:user)) }

      it 'does not record a link' do
        expect { created_note }.not_to change { Ai::DuoWorkflows::WorkflowNote.count }
      end
    end

    it 'does not fail note creation when finding the workflow raises' do
      allow(::Ai::DuoWorkflows::Workflow).to receive(:find_by_id).and_raise(StandardError)
      allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(StandardError), workflow_id: workflow.id.to_s)

      expect { created_note }.not_to change { Ai::DuoWorkflows::WorkflowNote.count }
      expect(created_note).to be_persisted
    end

    it 'does not fail note creation when linking raises' do
      allow(::Ai::DuoWorkflows::LinkArtifactService).to receive(:new).and_raise(StandardError)
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)

      expect(created_note).to be_persisted
    end

    context 'when a workplan flow posts a clarifying question' do
      let_it_be(:service_account) { create(:user, :service_account, developer_of: project) }

      let(:workflow) do
        create(:duo_workflows_workflow, project: project, user: service_account, service_account: service_account,
          workflow_definition: 'workplan/v1')
      end

      let(:payload) { { type: 'closed', question: 'Which provider?', options: [{ id: 'okta', label: 'Okta' }] } }
      let(:opts) do
        { note: "Which provider?\n\n```json:duo-question\n#{payload.to_json}\n```\n", noteable_type: 'Issue',
          noteable_id: issue.id }
      end

      subject(:created_note) { described_class.new(project, service_account, opts).execute }

      before do
        stub_licensed_features(ai_workflows: true)
        allow(service_account).to receive(:allowed_to_use?).with(:duo_agent_platform, anything).and_return(true)
      end

      it 'records the question as an open decision on the thread' do
        expect { created_note }.to change { WorkItems::Decision.count }.by(1)

        expect(WorkItems::Decision.order(:id).last).to have_attributes(
          title: 'Which provider?',
          discussion_id: created_note.discussion_id,
          workflow: workflow,
          resolved_at: nil
        )
      end

      it 'does not fail note creation when recording the decision raises' do
        allow(::WorkItems::Decisions::CreateFromDuoQuestionService).to receive(:new).and_raise(StandardError)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), hash_including(workflow_id: workflow.id))

        expect(created_note).to be_persisted
      end
    end
  end

  context 'when a type changing quick action is rejected' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:epic) { create(:work_item, :epic, namespace: group) }
    let_it_be(:issue, freeze: false) { create(:work_item, :issue, project: project) }

    before_all do
      create(:parent_link, work_item: issue, work_item_parent: epic)
    end

    before do
      stub_licensed_features(epics: true, subepics: true)
    end

    it 'reports the error without the promote_to_incident success message', :aggregate_failures do
      note = described_class.new(project, user, noteable: issue, note: '/promote_to_incident').execute

      expect(issue.reload.work_item_type.name).to eq('Issue')
      expect(note.quick_actions_status.error?).to be(true)
      expect(note.quick_actions_status.messages).to be_empty
      expect(note.quick_actions_status.error_messages)
        .to eq(['Work item type cannot be changed to incident when linked to a parent epic.'])
    end

    it 'keeps the type error when promote_to_incident is also rejected', :aggregate_failures do
      note = described_class.new(project, user, noteable: issue,
        note: "/type Nonexistent\n/promote_to_incident").execute

      expect(note.quick_actions_status.messages)
        .to eq(['Failed to convert this work item: Provided type is not supported.'])
    end
  end
end
