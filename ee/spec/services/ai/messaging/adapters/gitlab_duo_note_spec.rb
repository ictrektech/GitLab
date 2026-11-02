# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::Adapters::GitlabDuoNote, feature_category: :dap_code_review do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
  let_it_be(:author) { create(:user) }
  let_it_be(:note) do
    create(:diff_note_on_merge_request, noteable: merge_request, project: project, author: author)
  end

  let_it_be(:duo_bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

  let(:ctx) do
    {
      'note_id' => note.id,
      'note_author_id' => duo_bot.id
    }
  end

  subject(:adapter) { described_class.from_callback_context(ctx) }

  describe '.adapter_key' do
    it { expect(described_class.adapter_key).to eq('gitlab_duo_note') }
  end

  describe '.for_note' do
    it 'builds an adapter that serializes the note id and author id' do
      adapter = described_class.for_note(note, note_author_id: duo_bot.id)

      expect(adapter.build_callback_context).to eq(
        'adapter' => 'gitlab_duo_note',
        'note_id' => note.id,
        'note_author_id' => duo_bot.id,
        'force_internal' => false
      )
    end

    it 'serializes an explicit force_internal: true (e.g. security_review/v1)' do
      adapter = described_class.for_note(note, note_author_id: duo_bot.id, force_internal: true)

      expect(adapter.build_callback_context).to eq(
        'adapter' => 'gitlab_duo_note',
        'note_id' => note.id,
        'note_author_id' => duo_bot.id,
        'force_internal' => true
      )
    end
  end

  describe '.for_note with a scoped user' do
    it 'serializes the scoped user id' do
      adapter = described_class.for_note(note, note_author_id: duo_bot.id, scoped_user_id: author.id)

      expect(adapter.build_callback_context).to include('scoped_user_id' => author.id)
    end
  end

  describe '.from_callback_context' do
    it 'returns an instance of the adapter' do
      expect(described_class.from_callback_context(ctx)).to be_a(described_class)
    end
  end

  describe '#on_request_received' do
    it 'returns ServiceResponse.success' do
      expect(adapter.on_request_received).to be_success
    end

    context 'when note is not found' do
      let(:ctx) { super().merge('note_id' => non_existing_record_id) }

      it 'returns ServiceResponse.error' do
        result = adapter.on_request_received

        expect(result).to be_error
        expect(result.message).to eq('Note not found')
      end
    end

    context 'when the note has no noteable' do
      before do
        allow_next_found_instance_of(Note) do |found_note|
          allow(found_note).to receive(:noteable).and_return(nil)
        end
      end

      it 'returns ServiceResponse.error' do
        result = adapter.on_request_received

        expect(result).to be_error
        expect(result.message).to eq('Noteable not found')
      end
    end
  end

  describe '#on_flow_enqueued' do
    let_it_be_with_reload(:workflow) { create(:duo_workflows_workflow, project: project, user: author) }

    before do
      stub_feature_flags(note_agent_session_bar: project)
    end

    it 'does not post a started note or store started_note_id', :aggregate_failures do
      expect { adapter.on_flow_enqueued(callback_context: ctx, workflow: workflow) }
        .not_to change { Note.count }

      expect(workflow.reload.messaging_callback_context.to_h).not_to have_key('started_note_id')
    end

    context 'when note_agent_session_bar is disabled' do
      before do
        stub_feature_flags(note_agent_session_bar: false)
      end

      it 'posts a duo_mention_started note in the discussion thread and stores its id in messaging_callback_context',
        :aggregate_failures do
        adapter.on_flow_enqueued(callback_context: ctx, workflow: workflow)

        started_note = Note.order(id: :desc).first
        expect(started_note.note).to include('started [session')
        expect(started_note.author).to eq(duo_bot)
        expect(started_note.discussion_id).to eq(note.discussion_id)
        expect(workflow.reload.messaging_callback_context['started_note_id']).to eq(started_note.id)
      end
    end

    # No time travel: the session bar has to appear even though the note was just
    # posted, which is inside the window where ThrottledTouch swallows touches.
    it 'links the triggering note to the workflow with link_type triggered and refreshes it',
      :aggregate_failures do
      fresh_workflow = create(:duo_workflows_workflow, project: project, user: author)

      expect { adapter.on_flow_enqueued(callback_context: ctx, workflow: fresh_workflow) }
        .to change { note.reload.updated_at }

      expect(Ai::DuoWorkflows::WorkflowNote.where(note: note, link_type: :triggered).count).to eq(1)
    end

    context 'when linking the triggering note fails' do
      before do
        stub_feature_flags(note_agent_session_bar: false)
        allow_next_instance_of(::Ai::DuoWorkflows::LinkArtifactService) do |svc|
          allow(svc).to receive(:execute).and_raise(StandardError)
        end
      end

      it 'does not refresh the note and still posts the started note' do
        expect { adapter.on_flow_enqueued(callback_context: ctx, workflow: workflow) }
          .to change { Note.count }.by(1)
          .and not_change { note.reload.updated_at }
      end
    end

    context 'when refreshing the triggering note raises' do
      before do
        stub_feature_flags(note_agent_session_bar: false)
        allow(workflow).to receive(:broadcast_triggering_notes_changed).and_raise(StandardError)
      end

      it 'tracks the error and still posts the started note' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(StandardError), workflow_id: workflow.id)

        expect { adapter.on_flow_enqueued(callback_context: ctx, workflow: workflow) }
          .to change { Note.count }.by(1)
      end
    end

    context 'when note is not found' do
      let(:ctx) { super().merge('note_id' => non_existing_record_id) }

      it 'does nothing' do
        expect { adapter.on_flow_enqueued(callback_context: ctx, workflow: workflow) }
          .not_to change { Note.count }
      end
    end

    context 'when author is not found' do
      let(:ctx) { super().merge('note_author_id' => non_existing_record_id) }

      it 'does nothing' do
        expect { adapter.on_flow_started(callback_context: ctx, workflow: workflow) }
          .not_to change { Note.count }
      end
    end
  end

  describe '#build_callback_context' do
    it 'returns a hash with adapter key, note_id, note_author_id, and force_internal' do
      result = adapter.build_callback_context

      expect(result).to eq(
        'adapter' => 'gitlab_duo_note',
        'note_id' => note.id,
        'note_author_id' => duo_bot.id,
        'force_internal' => false
      )
    end
  end

  describe '#deliver_result' do
    it 'posts a reply note in the original discussion', :aggregate_failures do
      # A composite-identity service-account author (e.g. the Duo Developer flow
      # SA) cannot post the reply in CallbackWorker without a linked human.
      expect(adapter).to receive(:link_composite_identity!)
        .with(duo_bot, note.author, note.project.organization).and_call_original

      result = nil
      expect { result = adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
        .to change { Note.count }.by(1)

      expect(result).to be(true)

      reply = Note.order(id: :desc).first
      expect(reply.note).to eq('Review done!')
      expect(reply.author).to eq(duo_bot)
      expect(reply.noteable).to eq(merge_request)
      # gitlab#606308: without an explicit force_internal request the reply is
      # PUBLIC by default (this is the historical/legacy behavior other
      # mention-triggered flows, e.g. developer/v1, still rely on).
      expect(reply.internal).to be(false)
    end

    it 'posts quick actions in the reply as literal text without running them', :aggregate_failures do
      message = "Done.\n/approve\n/merge"

      adapter.deliver_result(callback_context: ctx, message: message, workflow: nil)

      expect(Note.order(id: :desc).first.note).to eq(message)
      expect(merge_request.approved_by_users.reload).not_to include(duo_bot)
    end

    context 'when the callback context names a scoped user' do
      let_it_be(:root_user) { create(:user) }
      let(:ctx) { super().merge('scoped_user_id' => root_user.id) }

      it 'links the reply author to the scoped user instead of the mention author' do
        expect(adapter).to receive(:link_composite_identity!)
          .with(duo_bot, root_user, note.project.organization)

        adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil)
      end
    end

    context 'when force_internal is true (e.g. security_review/v1, gitlab#606308)' do
      let(:ctx) { super().merge('force_internal' => true) }

      it 'posts a NEW internal note plus a public pointer reply in the mention discussion', :aggregate_failures do
        expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
          .to change { Note.count }.by(2)

        pointer, internal_note = Note.order(id: :desc).first(2)

        expect(internal_note.note).to eq('Review done!')
        expect(internal_note.internal).to be(true)
        # One confidentiality state per discussion, so this cannot be threaded.
        expect(internal_note.discussion_id).not_to eq(note.discussion_id)

        # The mention thread still gets an answer: a public pointer, no review content.
        expect(pointer.internal).to be(false)
        expect(pointer.discussion_id).to eq(note.discussion_id)
        expect(pointer.note).to include(::Gitlab::UrlBuilder.build(internal_note))
        expect(pointer.note).to include("#note_#{internal_note.id}")
        expect(pointer.note).not_to include('Review done!')
      end

      it 'does not post a dangling pointer when the internal note fails to persist' do
        allow_next_instance_of(::Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(Note.new)
        end

        expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
          .not_to change { Note.count }
      end

      it 'logs a warning when the POINTER note fails to persist', :aggregate_failures do
        # Fail only the second CreateService call (the pointer); the internal
        # note must still land, which is exactly why the failure is otherwise
        # silent -- deliver_result reports success off the internal note.
        calls = 0
        allow(::Notes::CreateService).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          calls += 1
          next instance_double(::Notes::CreateService, execute: Note.new) if calls == 2

          method.call(*args, **kwargs)
        end

        expect(::Gitlab::AppLogger).to receive(:warn).with(
          hash_including(message: 'Failed to post pointer note for forced-internal mention reply')
        )

        expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
          .to change { Note.count }.by(1)
      end

      it 'posts NOTHING and reports failure so the delivery is retried ' \
        'when the author cannot mark the note as internal', :aggregate_failures do
        # With no parent discussion to inherit from, Notes::BuildService silently
        # drops a denied internal: and saves the note PUBLIC -- so this must be
        # caught BEFORE the write, not by inspecting the saved note.
        allow(::Ability).to receive(:allowed?).and_call_original
        allow(::Ability).to receive(:allowed?)
          .with(anything, :mark_note_as_internal, anything).and_return(false)

        expect(::Gitlab::AppLogger).to receive(:warn).with(
          hash_including(message: 'Cannot force an internal mention reply: author cannot mark notes as internal')
        )

        result = nil
        expect { result = adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
          .not_to change { Note.count }

        expect(result).to be(false)
      end

      it 'tracks the exception rather than failing delivery when the POINTER note raises', :aggregate_failures do
        # A raise here would fail the whole delivery, and the retry would re-run
        # create_note_on and post a SECOND internal note carrying the review.
        calls = 0
        allow(::Notes::CreateService).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          calls += 1
          raise 'pointer boom' if calls == 2

          method.call(*args, **kwargs)
        end

        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(RuntimeError), hash_including(:internal_note_id))

        expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
          .to change { Note.count }.by(1)
      end

      context 'and the mention note is already internal' do
        # The confidential column is the source of truth -- Note#set_internal_flag
        # derives the internal column from it before_create, so passing internal:
        # directly would leave the discussion non-confidential. Must also be a
        # plain note: a diff note cannot be confidential
        # (noteable_can_have_confidential_note? is for_issuable? || for_wiki_page?).
        let_it_be(:internal_mention) do
          create(:note_on_merge_request, noteable: merge_request, project: project, author: author,
            confidential: true)
        end

        let(:ctx) { super().merge('note_id' => internal_mention.id) }

        it 'threads the reply into the mention discussion with no pointer note', :aggregate_failures do
          expect(internal_mention.confidential?).to be(true)
          expect(internal_mention.internal).to be(true)
          expect(internal_mention.to_discussion.confidential?).to be(true)

          expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
            .to change { Note.count }.by(1)

          reply = Note.order(id: :desc).first

          expect(reply.note).to eq('Review done!')
          expect(reply.internal).to be(true)
          # The parent discussion is already internal, so its confidentiality
          # matches the reply and no separate note or pointer is needed.
          expect(reply.discussion_id).to eq(internal_mention.discussion_id)
        end
      end

      context 'and the noteable cannot hold an internal note' do
        # noteable_can_have_confidential_note? is for_issuable? || for_wiki_page?,
        # so a snippet note can never be internal. Splitting would fail validation
        # and, once the worker exhausts its retries, leave the mention unanswered.
        let_it_be(:snippet_mention) { create(:note_on_project_snippet, project: project, author: author) }

        let(:ctx) { super().merge('note_id' => snippet_mention.id) }

        # Exactly one note, exactly as an unforced reply would post it: no split,
        # no pointer, and nothing rejected by the confidentiality validation.
        it 'falls back to an ordinary public reply', :aggregate_failures do
          expect(snippet_mention.for_issuable?).to be(false)
          expect(snippet_mention.for_wiki_page?).to be(false)

          expect { adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil) }
            .to change { Note.count }.by(1)

          reply = Note.order(id: :desc).first

          expect(reply.note).to eq('Review done!')
          expect(reply.internal).to be(false)
          expect(reply.noteable).to eq(snippet_mention.noteable)
        end
      end
    end

    context 'when an AI service account reply contains a quick action it may not run', :request_store do
      let_it_be(:human) { create(:user, developer_of: project) }
      let_it_be(:service_account) { create(:user, :ai_service_account, developer_of: project) }
      let_it_be_with_reload(:mr) do
        create(:merge_request, source_project: project, target_project: project, source_branch: 'improve/awesome')
      end

      let_it_be(:mention) { create(:note_on_merge_request, noteable: mr, project: project, author: human) }
      let(:ctx) { { 'note_id' => mention.id, 'note_author_id' => service_account.id } }

      before do
        ::Gitlab::Auth::Identity.fabricate(service_account).link!(human)
      end

      it 'posts the reply with the blocked quick action as code and does not run it', :aggregate_failures do
        workflow = create(:duo_workflows_workflow, project: project, user: human)
        allow(::Gitlab::AppLogger).to receive(:warn).and_call_original

        result = nil
        expect { result = adapter.deliver_result(callback_context: ctx, message: "Done\n/close", workflow: workflow) }
          .to change { Note.user.count }.by(1)

        expect(result).to be(true)
        expect(Note.user.order(id: :desc).first.note).to start_with("Done\n`/close`")
          .and end_with("[View session](#{workflow.web_url})\n\nThese quick actions were not applied: `/close`")
        expect(mr.reload).to be_opened
        expect(::Gitlab::AppLogger).to have_received(:warn)
          .with(hash_including(
            message: 'Flow reply posted with blocked quick actions as code',
            blocked_quick_actions: a_string_including('close'),
            workflow_id: workflow.id
          ))
      end

      it 'still runs allowed quick actions next to a blocked one', :aggregate_failures do
        label = create(:label, project: project, title: 'reviewed')

        result = adapter.deliver_result(callback_context: ctx, message: "/label ~reviewed\n/close", workflow: nil)

        expect(result).to be(true)
        expect(Note.user.order(id: :desc).first.note)
          .to eq("`/close`\n\nThese quick actions were not applied: `/close`")
        expect(mr.reload).to be_opened
        expect(mr.labels).to contain_exactly(label)
      end

      it 'names each blocked quick action once in the line about quick actions not applied' do
        message = "Done\n/close\n/label ~reviewed\n/merge\n/close"

        adapter.deliver_result(callback_context: ctx, message: message, workflow: nil)

        expect(Note.user.order(id: :desc).first.note)
          .to end_with("\n\nThese quick actions were not applied: `/close`, `/merge`")
      end

      it 'does not name substitutions, which are still applied' do
        adapter.deliver_result(callback_context: ctx, message: "/shrug\n/close", workflow: nil)

        expect(Note.user.order(id: :desc).first.note)
          .to end_with("\n\nThese quick actions were not applied: `/close`")
      end

      it 'does not add the line when no quick action is blocked', :aggregate_failures do
        label = create(:label, project: project, title: 'checked')

        result = adapter.deliver_result(callback_context: ctx, message: "Done\n/label ~checked", workflow: nil)

        expect(result).to be(true)
        expect(Note.user.order(id: :desc).first.note).to eq('Done')
        expect(mr.reload.labels).to include(label)
      end

      it 'posts one reply when the description already has a blocked quick action', :aggregate_failures do
        label = create(:label, project: project, title: 'imported')
        mr.update_column(:description, "Imported\n/close")

        message = "Done\n/label ~imported"

        result = nil
        expect { result = adapter.deliver_result(callback_context: ctx, message: message, workflow: nil) }
          .to change { Note.user.count }.by(1)

        expect(result).to be(true)
        expect(Note.user.order(id: :desc).first.note).to eq('Done')
        expect(mr.reload).to be_opened
        expect(mr.labels).to contain_exactly(label)
      end

      it 'does not add the not-applied line when no quick action can be listed', :aggregate_failures do
        error = ::QuickActions::InterpretService::QuickActionsNotAllowedError.new('blocked')
        create_services = []
        allow(::Notes::CreateService).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |service|
            create_services << service
            allow(service).to receive(:execute).and_raise(error) if create_services.one?
          end
        end

        result = adapter.deliver_result(callback_context: ctx, message: 'Done', workflow: nil)

        expect(result).to be(true)
        expect(Note.user.order(id: :desc).first.note).to eq('Done')
        expect(create_services.size).to eq(2)
      end

      it 'raises when the redacted reply is still rejected' do
        error = ::QuickActions::InterpretService::QuickActionsNotAllowedError.new('blocked')
        create_services = []
        allow(::Notes::CreateService).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |service|
            create_services << service
            allow(service).to receive(:execute).and_raise(error)
          end
        end

        expect { adapter.deliver_result(callback_context: ctx, message: "Done\n/close", workflow: nil) }
          .to raise_error(error)
        expect(create_services.size).to eq(2)
      end
    end

    context 'when the reply note is rejected' do
      before do
        allow_next_instance_of(::Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(build(:note))
        end
      end

      it 'returns false so the caller can retry the delivery' do
        expect(adapter.deliver_result(callback_context: ctx, message: 'Review done!', workflow: nil)).to be(false)
      end
    end

    context 'when started_note_id is present in callback_context' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: author) }
      let_it_be(:started_note) do
        create(:note, project: project, noteable: merge_request).tap do |n|
          create(:note_duo_metadata, note: n, workflow_id: workflow.id, namespace_id: project.namespace_id)
        end
      end

      let(:ctx_with_started) { ctx.merge('started_note_id' => started_note.id) }

      it 'destroys the started note, appends a session link, and links the workflow to the reply',
        :aggregate_failures do
        expect { adapter.deliver_result(callback_context: ctx_with_started, message: 'Done', workflow: workflow) }
          .to change { Note.exists?(started_note.id) }.from(true).to(false)
          .and change { Ai::DuoWorkflows::WorkflowNote.count }.by(1)

        reply = Note.order(id: :desc).first
        expect(reply.note).to include('Done')
        expect(reply.note).to include("[View session](#{workflow.web_url})")

        link = Ai::DuoWorkflows::WorkflowNote.order(:id).last
        expect(link).to have_attributes(
          workflow: workflow,
          note_id: reply.id,
          link_type: 'created'
        )
      end

      it 'does not fail delivery when linking raises', :aggregate_failures do
        allow(::Ai::DuoWorkflows::LinkArtifactService).to receive(:new).and_raise(StandardError)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        # started_note is destroyed (-1) and the reply is created (+1), so Note.count nets to 0.
        expect { adapter.deliver_result(callback_context: ctx_with_started, message: 'Done', workflow: workflow) }
          .to not_change { Note.count }
          .and not_change { Ai::DuoWorkflows::WorkflowNote.count }

        reply = Note.order(id: :desc).first
        expect(reply.note).to include('Done')
      end

      context 'when destroying the started note fails' do
        before do
          allow_next_found_instance_of(::Note) do |n|
            allow(n).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)
          end
        end

        it 'tracks the error and still posts the reply' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(ActiveRecord::RecordNotDestroyed), note_id: started_note.id)

          expect { adapter.deliver_result(callback_context: ctx_with_started, message: 'Done', workflow: workflow) }
            .to change { Note.count }.by(1)
        end
      end
    end

    context 'when message is blank' do
      it 'does not create a note when there is no workflow (no session link to append)' do
        expect { adapter.deliver_result(callback_context: ctx, message: '', workflow: nil) }
          .not_to change { Note.count }
      end

      context 'when started_note_id is present (workflow available)' do
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: author) }
        let!(:started_note) do
          create(:note, project: project, noteable: merge_request).tap do |n|
            create(:note_duo_metadata, note: n, workflow_id: workflow.id, namespace_id: project.namespace_id)
          end
        end

        let(:ctx_with_started) { ctx.merge('started_note_id' => started_note.id) }

        it 'still posts the session link even when the result message is blank' do
          # append_session_link drops the blank message but keeps the session link,
          # so the reply note contains only the link (not swallowed by the blank-content guard).
          # Note.count stays the same: started_note is destroyed (-1) and the reply is created (+1).
          expect { adapter.deliver_result(callback_context: ctx_with_started, message: '', workflow: workflow) }
            .not_to change { Note.count }

          reply = Note.order(id: :desc).first
          expect(reply.note).to include("[View session](#{workflow.web_url})")
          expect(reply.note).not_to start_with("\n\n")
        end
      end
    end
  end

  describe '#deliver_error' do
    using RSpec::Parameterized::TableSyntax

    let(:goal_context_message) { "I can't run a code review in this context. Please try again on a merge request." }

    before do
      stub_feature_flags(note_agent_session_bar: false)
    end

    where(:error, :expected_text, :expected_url_fragment) do
      :service_account_error | 'Code Review Flow is enabled' | nil
      :execute_workflow_failed | 'Failed to start the Duo workflow. Please try again.' | nil
      :flow_failed | 'Something went wrong while running the task. Please try again.' | nil
      :flow_stopped | 'The session was stopped before it finished.' | nil
      :no_response | 'The workflow completed but no response was produced. Please try again.' | nil
      :message_too_long | 'Your message is too long for me to process. Shorten it and mention me again.' | nil
      :invalid_goal | ref(:goal_context_message) | nil
      :unsupported_resource_type | ref(:goal_context_message) | nil
      :no_eligible_runner | 'no runner available' | 'a-flows-job-or-session-fails-to-start'
      :namespace_ci_minutes_used_up | 'run out of compute minutes' | nil
      :unknown_error | 'Something went wrong. Please try again.' | nil
    end

    with_them do
      it 'posts the correct error note text', :aggregate_failures do
        adapter.deliver_error(callback_context: ctx.dup, error: error)

        note_text = Note.order(id: :desc).first.note
        expect(note_text).to include(expected_text)
        expect(note_text).to include(expected_url_fragment) if expected_url_fragment
      end
    end

    context 'with :no_eligible_runner' do
      it 'names the tag the project routes to' do
        adapter.deliver_error(callback_context: ctx.dup, error: :no_eligible_runner)

        expect(Note.order(id: :desc).first.note).to include('`gitlab--duo--suspendable`')
      end

      context 'when suspendable_workload_tag_for_dap is disabled' do
        before do
          stub_feature_flags(suspendable_workload_tag_for_dap: false)
        end

        it 'names the default tag' do
          adapter.deliver_error(callback_context: ctx.dup, error: :no_eligible_runner)

          expect(Note.order(id: :desc).first.note).to include('`gitlab--duo`')
        end
      end
    end

    context 'when force_internal is true (e.g. security_review/v1, gitlab#606308)' do
      let(:ctx) { super().merge('force_internal' => true) }

      it 'posts an internal error note plus a public pointer with error wording', :aggregate_failures do
        expect { adapter.deliver_error(callback_context: ctx, error: :flow_failed) }
          .to change { Note.count }.by(2)

        pointer, internal_note = Note.order(id: :desc).first(2)

        expect(internal_note.internal).to be(true)
        expect(internal_note.note).to include('Something went wrong while running the task.')

        # The pointer must describe a FAILED review, not claim completion.
        expect(pointer.internal).to be(false)
        expect(pointer.discussion_id).to eq(note.discussion_id)
        expect(pointer.note).to include('The task could not be completed.')
        expect(pointer.note).to include("#note_#{internal_note.id}")
        expect(pointer.note).not_to include('I have posted my response')
      end
    end

    context 'when started_note_id is present in callback_context' do
      let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: author) }
      let_it_be(:started_note) do
        create(:note, project: project, noteable: merge_request).tap do |n|
          create(:note_duo_metadata, note: n, workflow_id: workflow.id, namespace_id: project.namespace_id)
        end
      end

      let(:ctx_with_started) { ctx.merge('started_note_id' => started_note.id) }

      it 'destroys the started note and links the workflow to the error note', :aggregate_failures do
        expect { adapter.deliver_error(callback_context: ctx_with_started, error: :flow_failed) }
          .to change { Note.exists?(started_note.id) }.from(true).to(false)
          .and change { Ai::DuoWorkflows::WorkflowNote.count }.by(1)

        error_note = Note.order(id: :desc).first
        link = Ai::DuoWorkflows::WorkflowNote.order(:id).last
        expect(link).to have_attributes(
          workflow: workflow,
          note_id: error_note.id,
          link_type: 'created'
        )
      end

      it 'does not fail delivery when linking raises', :aggregate_failures do
        allow(::Ai::DuoWorkflows::LinkArtifactService).to receive(:new).and_raise(StandardError)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        # started_note is destroyed (-1) and the error note is created (+1), so Note.count nets to 0.
        expect { adapter.deliver_error(callback_context: ctx_with_started, error: :flow_failed) }
          .to not_change { Note.count }
          .and not_change { Ai::DuoWorkflows::WorkflowNote.count }

        error_note = Note.order(id: :desc).first
        expect(error_note.note).to include('Something went wrong while running the task')
      end
    end

    context 'when started_note_id is absent (workflow has not started yet)' do
      it 'posts the error note without creating a workflow link' do
        expect { adapter.deliver_error(callback_context: ctx, error: :flow_failed) }
          .to change { Note.count }.by(1)
          .and not_change { Ai::DuoWorkflows::WorkflowNote.count }
      end
    end

    context 'when the note_agent_session_bar feature flag is enabled' do
      before do
        stub_feature_flags(note_agent_session_bar: project)
      end

      where(:error) { [:flow_failed, :flow_stopped] }

      with_them do
        it 'does not post an error note' do
          expect { adapter.deliver_error(callback_context: ctx, error: error) }.not_to change { Note.count }
        end
      end

      it 'still posts error notes for other errors' do
        expect { adapter.deliver_error(callback_context: ctx, error: :no_response) }
          .to change { Note.count }.by(1)
      end

      context 'when a started note is in flight' do
        let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: author) }
        let_it_be(:started_note) do
          create(:note, project: project, noteable: merge_request).tap do |n|
            create(:note_duo_metadata, note: n, workflow_id: workflow.id, namespace_id: project.namespace_id)
          end
        end

        let(:ctx_with_started) { ctx.merge('started_note_id' => started_note.id) }

        with_them do
          it 'still destroys the started note without posting an error note', :aggregate_failures do
            expect { adapter.deliver_error(callback_context: ctx_with_started, error: error) }
              .to change { Note.exists?(started_note.id) }.from(true).to(false)
              .and change { Note.count }.by(-1)
              .and not_change { Ai::DuoWorkflows::WorkflowNote.count }
          end
        end
      end

      context 'when the note is not found' do
        let(:ctx) { super().merge('note_id' => non_existing_record_id) }

        where(:error) { [:flow_failed, :flow_stopped] }

        with_them do
          it 'does not post an error note' do
            expect { adapter.deliver_error(callback_context: ctx, error: error) }.not_to change { Note.count }
          end
        end
      end
    end
  end
end
