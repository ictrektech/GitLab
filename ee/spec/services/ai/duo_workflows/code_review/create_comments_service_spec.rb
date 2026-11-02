# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::CreateCommentsService, feature_category: :dap_code_review do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:review_bot) { create(:user, :duo_code_review_bot) }

  let(:review_output) { '{"comments": []}' }
  let(:workflow_id) { nil }
  let(:progress_note) { nil }
  let(:service) do
    described_class.new(
      user: user,
      merge_request: merge_request,
      review_output: review_output,
      progress_note: progress_note,
      workflow_id: workflow_id
    )
  end

  describe '#execute' do
    subject(:execute) { service.execute }

    context 'when progress note is present' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:process_result) { ServiceResponse.success(message: 'Success', payload: { draft_notes: [] }) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)
      end

      it 'deletes the progress note in ensure block' do
        expect(progress_note).to receive(:destroy)
        execute
      end

      it 'updates review state to reviewed' do
        expect_next_instance_of(MergeRequests::UpdateReviewerStateService) do |instance|
          expect(instance).to receive(:execute).with(merge_request, 'reviewed')
        end
        execute
      end
    end

    context 'when ProcessCommentsService returns an error' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:error_message) { 'Processing failed' }
      let(:process_result) do
        ServiceResponse.error(
          message: error_message,
          payload: { create_todo: true }
        )
      end

      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns an error response' do
        expect(execute).to be_error
        expect(execute.message).to eq(error_message)
      end

      it 'updates progress note with todo' do
        expect(service).to receive(:update_progress_note).with(error_message, with_todo: true)
        execute
      end
    end

    context 'when ProcessCommentsService returns an error without create_todo in payload' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:error_message) { 'Processing failed' }
      let(:process_result) { ServiceResponse.error(message: error_message, payload: {}) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns an error response' do
        expect(execute).to be_error
      end

      it 'updates progress note without creating a todo' do
        expect(service).to receive(:update_progress_note).with(error_message, with_todo: false)
        execute
      end
    end

    context 'when ProcessCommentsService returns success with draft notes' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:draft_note) { instance_double(DraftNote) }
      let(:draft_notes) { [draft_note] }
      let(:summary) { 'Review summary' }
      let(:metrics) do
        instance_double(
          Ai::DuoWorkflows::CodeReview::ProcessCommentsService::Metrics,
          total_comments: 1,
          comments_with_valid_path: 1,
          comments_with_valid_line: 1,
          comments_with_custom_instructions: 0,
          comments_line_matched_by_content: 0,
          draft_notes_created: 1,
          comments_by_severity: {}
        )
      end

      let(:process_result) do
        ServiceResponse.success(
          message: summary,
          payload: {
            draft_notes: draft_notes,
            metrics: metrics
          }
        )
      end

      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      let(:publish_service) { instance_double(DraftNotes::PublishService, execute: { status: :success }) }

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService).to receive(:new).and_return(process_service)
        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(true)
        allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
        allow(DraftNotes::PublishService).to receive(:new).and_return(publish_service)
        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(service).to receive(:track_review_merge_request_event)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns success' do
        expect(execute).to be_success
      end

      it 'publishes draft notes' do
        expect(DraftNote).to receive(:bulk_insert_and_keep_commits!).with(draft_notes, batch_size: 20)
        expect(DraftNotes::PublishService).to receive(:new)
          .with(merge_request, review_bot, hash_including(:summary_note)).and_return(publish_service)
        expect(publish_service).to receive(:execute).with(executing_user: user).and_return({ status: :success })
        execute
      end

      it 'logs metrics' do
        expect(service).to receive(:log_metrics).with(metrics)
        execute
      end

      it 'tracks the correct event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('post_comment_duo_code_review_on_diff', additional_properties: { value: 1 })
        execute
      end
    end

    context 'when ProcessCommentsService returns success with no draft notes' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:message) { 'No comments to add' }
      let(:process_result) do
        ServiceResponse.success(
          message: message,
          payload: { draft_notes: [] }
        )
      end

      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(service).to receive(:track_review_merge_request_event)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns success' do
        expect(execute).to be_success
      end

      it 'updates progress note with todo' do
        expect(service).to receive(:update_progress_note).with(message, with_todo: true)
        execute
      end

      it 'tracks the no issues event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')
        execute
      end

      it 'does not publish draft notes' do
        expect(service).not_to receive(:publish_draft_notes)
        execute
      end
    end

    context 'when draft_notes key is absent from the ProcessCommentsService payload' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:process_result) { ServiceResponse.success(message: 'OK', payload: {}) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(service).to receive(:track_review_merge_request_event)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns success' do
        expect(execute).to be_success
      end

      it 'takes the empty-notes path without raising' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')
        execute
      end
    end

    context 'when progress_note is nil' do
      # Uses the top-level default: let(:progress_note) { nil }
      let(:process_result) { ServiceResponse.success(message: 'OK', payload: { draft_notes: [] }) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_review_state)
        allow(service).to receive(:track_review_merge_request_event)
      end

      it 'returns success without raising' do
        expect(execute).to be_success
      end

      it 'does not create any notes' do
        expect(Notes::CreateService).not_to receive(:new)
        execute
      end
    end

    context 'when a StandardError occurs' do
      let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
      let(:error) { StandardError.new('Something went wrong') }

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_raise(error)

        allow(service).to receive(:track_review_merge_request_exception)
        allow(service).to receive(:track_review_merge_request_event)
        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(progress_note).to receive(:destroy)
      end

      it 'returns an error with generic message' do
        expect(execute).to be_error
        expect(execute.message).to include('I have encountered some problems')
      end

      it 'tracks the exception' do
        expect(service).to receive(:track_review_merge_request_exception).with(error)
        execute
      end

      it 'tracks the error event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('encounter_duo_code_review_error_during_review')
        execute
      end

      it 'updates progress note with todo' do
        expect(service).to receive(:update_progress_note)
          .with(a_string_including('I have encountered some problems'), with_todo: true)
        execute
      end

      it 'still cleans up resources' do
        expect(progress_note).to receive(:destroy)
        expect(service).to receive(:update_review_state).with('reviewed')
        execute
      end
    end
  end

  describe 'recording a review decision' do
    subject(:execute) { service.execute }

    let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
    let(:no_issues_found) { false }
    let(:draft_notes) { [] }
    let(:metrics) { Ai::DuoWorkflows::CodeReview::ProcessCommentsService::Metrics.new }

    let(:process_result) do
      ServiceResponse.success(
        message: 'Review complete',
        payload: {
          draft_notes: draft_notes,
          metrics: metrics,
          no_issues_found: no_issues_found
        }
      )
    end

    let(:process_service) do
      instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
    end

    before do
      stub_feature_flags(duo_code_review_response_logging: false)
      allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
        .to receive(:new).and_return(process_service)
      allow(service).to receive(:update_progress_note)
      allow(service).to receive(:track_review_merge_request_event)
      allow(progress_note).to receive(:destroy)
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(true)
    end

    shared_examples 'reaches no decision' do
      it 'marks the review as reviewed without approving' do
        expect(MergeRequests::ApprovalService).not_to receive(:new)
        expect(service).to receive(:update_review_state).with('reviewed')

        execute
      end
    end

    context 'when decisions are enabled' do
      before do
        allow(project).to receive(:duo_code_review_available?).and_return(true)
        project.update!(duo_code_review_decisions_enabled: true)
      end

      context 'when no issues were found' do
        let(:no_issues_found) { true }

        it 'does not fall back to marking the review as reviewed' do
          allow_next_instance_of(MergeRequests::ApprovalService) do |instance|
            allow(instance).to receive(:execute).and_return(ServiceResponse.success)
          end

          expect(service).not_to receive(:update_review_state).with('reviewed')

          execute
        end

        it 'approves through the real approval service and tracks the approval', :clean_gitlab_redis_shared_state do
          allow(service).to receive(:track_review_merge_request_event).and_call_original

          expect { execute }
            .to trigger_internal_events('approve_merge_request_duo_code_review')
            .with(user: user, project: project, additional_properties: { property: merge_request.id.to_s })
            .and increment_usage_metrics(
              'counts.count_total_approve_merge_request_duo_code_review',
              'counts.count_total_approve_merge_request_duo_code_review_monthly',
              'counts.count_total_approve_merge_request_duo_code_review_weekly',
              'redis_hll_counters.count_distinct_property_from_approve_merge_request_duo_code_review_monthly',
              'redis_hll_counters.count_distinct_property_from_approve_merge_request_duo_code_review_weekly'
            )

          expect(merge_request.approved_by_users.reload).to include(review_bot)
        end

        context 'when the approval fails' do
          before do
            allow_next_instance_of(MergeRequests::ApprovalService) do |instance|
              allow(instance).to receive(:execute).and_return(ServiceResponse.error(message: 'error'))
            end
            allow(service).to receive(:track_review_merge_request_event).and_call_original
          end

          it 'does not track the approval' do
            expect { execute }.not_to trigger_internal_events('approve_merge_request_duo_code_review')
          end
        end
      end

      context 'when comments were left' do
        let(:draft_notes) { [build(:draft_note, merge_request: merge_request, author: review_bot)] }

        before do
          allow(service).to receive(:publish_draft_notes)
          allow(service).to receive(:update_review_state).and_return({ status: :success })
        end

        it 'requests changes' do
          expect(service).to receive(:update_review_state).with('requested_changes')

          execute
        end

        it 'does not approve' do
          expect(MergeRequests::ApprovalService).not_to receive(:new)

          execute
        end
      end

      context 'when no comments were left' do
        it 'marks the review as reviewed' do
          expect(service).to receive(:update_review_state).with('reviewed')

          execute
        end

        context 'when the bot already requested changes on an earlier review' do
          before do
            create(:merge_request_requested_changes, merge_request: merge_request, project: project, user: review_bot)
          end

          it 'marks the review as reviewed and leaves the standing request in place' do
            expect(service).to receive(:update_review_state).with('reviewed')

            expect { execute }.not_to change {
              MergeRequests::RequestedChange.where(merge_request: merge_request).count
            }
          end
        end
      end
    end

    context 'when the project setting is off' do
      let(:no_issues_found) { true }

      before do
        allow(project).to receive(:duo_code_review_available?).and_return(true)
        project.update!(duo_code_review_decisions_enabled: false)
      end

      it_behaves_like 'reaches no decision'
    end

    context 'when the user cannot create notes' do
      let(:no_issues_found) { true }

      before do
        allow(project).to receive(:duo_code_review_available?).and_return(true)
        project.update!(duo_code_review_decisions_enabled: true)
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(false)
      end

      it_behaves_like 'reaches no decision'
    end

    context 'when the duo_code_review_decisions feature flag is disabled' do
      let(:no_issues_found) { true }

      before do
        stub_feature_flags(duo_code_review_decisions: false)
        allow(project).to receive(:duo_code_review_available?).and_return(true)
        project.update!(duo_code_review_decisions_enabled: true)
      end

      it_behaves_like 'reaches no decision'
    end
  end

  describe '#publish_draft_notes' do
    let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }
    let(:draft_note) { instance_double(DraftNote) }
    let(:draft_notes) { [draft_note] }
    let(:summary) { 'Review summary' }

    context 'when user can create notes' do
      let(:publish_service) { instance_double(DraftNotes::PublishService) }

      before do
        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(true)
        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:track_review_merge_request_event)
      end

      it 'bulk inserts draft notes and publishes them with the summary note' do
        expect(DraftNote).to receive(:bulk_insert_and_keep_commits!)
          .with(draft_notes, batch_size: 20)
        expect(DraftNotes::PublishService).to receive(:new)
          .with(
            merge_request,
            review_bot,
            { summary_note: { noteable: merge_request, note: summary, workflow_id: nil } }
          )
          .and_return(publish_service)
        expect(publish_service).to receive(:execute).with(executing_user: user).and_return({ status: :success })
        expect(service).not_to receive(:update_progress_note)

        service.send(:publish_draft_notes, draft_notes, summary, {})
      end

      it 'stores the findings of the published review' do
        workflow = build_stubbed(:duo_workflows_workflow)
        allow(service).to receive(:workflow).and_return(workflow)
        comments_by_draft_note = { draft_note => instance_double(Gitlab::Duo::CodeReview::FindingsParser::Comment) }
        allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
        publish_result = { status: :success, review_id: non_existing_record_id }
        allow(DraftNotes::PublishService).to receive(:new)
          .and_return(instance_double(DraftNotes::PublishService, execute: publish_result))

        expect_next_instance_of(
          Ai::DuoWorkflows::CodeReview::StoreFindingsService,
          merge_request: merge_request,
          review_id: non_existing_record_id,
          comments_by_draft_note: comments_by_draft_note,
          workflow: workflow
        ) do |store_service|
          expect(store_service).to receive(:execute)
        end

        service.send(:publish_draft_notes, draft_notes, summary, comments_by_draft_note)
      end

      context 'when progress_note is nil' do
        let(:progress_note) { nil }

        it 'publishes the draft notes without a summary note' do
          allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
          expect(DraftNotes::PublishService).to receive(:new)
            .with(merge_request, review_bot, {})
            .and_return(instance_double(DraftNotes::PublishService, execute: { status: :success }))

          service.send(:publish_draft_notes, draft_notes, summary, {})
        end
      end

      context 'when improved_review_email is disabled' do
        before do
          stub_feature_flags(improved_review_email: false)
        end

        it 'updates progress note with summary' do
          allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
          expect(DraftNotes::PublishService).to receive(:new)
            .with(merge_request, review_bot, {})
            .and_return(instance_double(DraftNotes::PublishService, execute: { status: :success }))

          expect(service).to receive(:update_progress_note).with(summary)

          service.send(:publish_draft_notes, draft_notes, summary, {})
        end
      end

      it 'tracks the comment event with count' do
        allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
        publish_service = instance_double(DraftNotes::PublishService, execute: { status: :success })
        allow(DraftNotes::PublishService).to receive(:new).and_return(publish_service)

        expect(service).to receive(:track_review_merge_request_event)
          .with('post_comment_duo_code_review_on_diff', additional_properties: { value: 1 })

        service.send(:publish_draft_notes, draft_notes, summary, {})
      end
    end

    context 'when user cannot create notes' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(false)
      end

      it 'does not publish draft notes' do
        expect(DraftNote).not_to receive(:bulk_insert_and_keep_commits!)
        expect(DraftNotes::PublishService).not_to receive(:new)

        service.send(:publish_draft_notes, draft_notes, summary, {})
      end
    end

    context 'when draft notes are empty' do
      let(:draft_notes) { [] }

      before do
        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(true)
      end

      it 'does not publish draft notes' do
        expect(DraftNote).not_to receive(:bulk_insert_and_keep_commits!)
        expect(DraftNotes::PublishService).not_to receive(:new)

        service.send(:publish_draft_notes, draft_notes, summary, {})
      end
    end
  end

  describe '#log_metrics' do
    let(:metrics) do
      instance_double(
        Ai::DuoWorkflows::CodeReview::ProcessCommentsService::Metrics,
        total_comments: 5,
        comments_with_valid_path: 4,
        comments_with_valid_line: 3,
        comments_with_custom_instructions: 1,
        comments_line_matched_by_content: 2,
        draft_notes_created: 3,
        comments_by_severity: { 'critical' => 2, 'major' => 1 }
      )
    end

    context 'when duo_code_review_response_logging is enabled' do
      before do
        stub_feature_flags(duo_code_review_response_logging: true)
        allow(service).to receive(:log_review_merge_request_event)
      end

      it 'logs the metrics with correct attributes' do
        expect(service).to receive(:log_review_merge_request_event).with(
          message: "LLM response comments metrics",
          event: "review_merge_request_llm_response_comments",
          merge_request_id: merge_request.id,
          total_comments: 5,
          comments_with_valid_path: 4,
          comments_with_valid_line: 3,
          comments_with_custom_instructions: 1,
          comments_line_matched_by_content: 2,
          draft_notes_created: 3,
          comments_by_severity: { 'critical' => 2, 'major' => 1 }
        )

        service.send(:log_metrics, metrics)
      end
    end

    context 'when duo_code_review_response_logging is disabled' do
      before do
        stub_feature_flags(duo_code_review_response_logging: false)
        allow(service).to receive(:log_review_merge_request_event)
      end

      it 'does not log metrics' do
        expect(service).not_to receive(:log_review_merge_request_event)

        service.send(:log_metrics, metrics)
      end
    end
  end

  describe '#update_review_state' do
    let(:update_service) { instance_double(MergeRequests::UpdateReviewerStateService) }

    before do
      allow(Users::Internal).to receive(:duo_code_review_bot).and_return(review_bot)
    end

    it 'calls UpdateReviewerStateService' do
      expect(MergeRequests::UpdateReviewerStateService).to receive(:new)
        .with(project: project, current_user: review_bot, review_workflow_id: nil)
        .and_return(update_service)
      expect(update_service).to receive(:execute).with(merge_request, 'reviewed')

      service.send(:update_review_state, 'reviewed')
    end

    context 'with a review workflow' do
      let_it_be(:workflow) do
        create(:duo_workflows_workflow, project: project, user: user,
          workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference)
      end

      let(:workflow_id) { workflow.id }

      before_all do
        project.add_developer(user)
      end

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        stub_ee_application_setting(duo_features_enabled: true)
        allow(user).to receive(:allowed_to_use?).with(:duo_agent_platform, anything).and_return(true)
      end

      it 'passes the review workflow to UpdateReviewerStateService' do
        expect(MergeRequests::UpdateReviewerStateService).to receive(:new)
          .with(project: project, current_user: review_bot, review_workflow_id: workflow.id)
          .and_return(update_service)
        expect(update_service).to receive(:execute).with(merge_request, 'requested_changes')

        service.send(:update_review_state, 'requested_changes')
      end

      context 'when the user cannot update the review workflow' do
        let(:workflow_id) do
          create(:duo_workflows_workflow, project: project, user: create(:user),
            workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference).id
        end

        it 'does not pass the workflow to UpdateReviewerStateService' do
          expect(MergeRequests::UpdateReviewerStateService).to receive(:new)
            .with(project: project, current_user: review_bot, review_workflow_id: nil)
            .and_return(update_service)
          expect(update_service).to receive(:execute).with(merge_request, 'requested_changes')

          service.send(:update_review_state, 'requested_changes')
        end
      end
    end

    context 'when merge_request is nil' do
      let(:merge_request) { nil }

      it 'does not call UpdateReviewerStateService' do
        expect(MergeRequests::UpdateReviewerStateService).not_to receive(:new)

        service.send(:update_review_state, 'reviewed')
      end
    end
  end

  describe 'comprehensive error handling' do
    subject(:execute) { service.execute }

    let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }

    context 'when ProcessCommentsService raises StandardError' do
      let(:original_error) { StandardError.new('Processing failed') }

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_raise(original_error)

        allow(service).to receive(:track_review_merge_request_exception)
        allow(service).to receive(:track_review_merge_request_event)
        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(progress_note).to receive(:destroy)
      end

      it 'handles the error gracefully' do
        result = execute
        expect(result).to be_error
        expect(result.message).to include('I have encountered some problems')
      end

      it 'tracks the original exception' do
        expect(service).to receive(:track_review_merge_request_exception).with(original_error)
        execute
      end

      it 'tracks the error event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('encounter_duo_code_review_error_during_review')
        execute
      end

      it 'updates progress note with generic error message' do
        expect(service).to receive(:update_progress_note)
          .with(a_string_including('I have encountered some problems'), with_todo: true)
        execute
      end

      it 'still performs cleanup in ensure block' do
        expect(service).to receive(:update_review_state).with('reviewed')
        expect(progress_note).to receive(:destroy)
        execute
      end
    end

    context 'when update_progress_note fails' do
      let(:process_result) { ServiceResponse.success(message: 'Success', payload: { draft_notes: [] }) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      let(:notes_error) { StandardError.new('Notes service failed') }

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note).and_raise(notes_error)
        allow(service).to receive(:track_review_merge_request_exception)
        allow(service).to receive(:track_review_merge_request_event)
        allow(service).to receive(:update_review_state)
        allow(progress_note).to receive(:destroy)
      end

      it 'allows notes service errors to propagate' do
        expect { execute }.to raise_error(StandardError, 'Notes service failed')
      end

      it 'still tracks the original exception before the notes error' do
        expect(service).to receive(:track_review_merge_request_exception).ordered
        expect { execute }.to raise_error(StandardError, 'Notes service failed')
      end
    end

    context 'when progress_note destruction fails' do
      let(:process_result) { ServiceResponse.success(message: 'Success', payload: { draft_notes: [] }) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:update_review_state)
        allow(service).to receive(:track_review_merge_request_event)
        allow(progress_note).to receive(:destroy).and_raise('Destruction failed')
      end

      it 'allows destruction errors to propagate' do
        expect { execute }.to raise_error('Destruction failed')
      end
    end

    context 'when review state update fails' do
      let(:process_result) { ServiceResponse.success(message: 'Success', payload: { draft_notes: [] }) }
      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(service).to receive(:update_progress_note)
        allow(service).to receive(:track_review_merge_request_event)
        allow(service).to receive(:update_review_state).and_raise('State update failed')
        allow(progress_note).to receive(:destroy)
      end

      it 'allows state update errors to propagate' do
        expect { execute }.to raise_error('State update failed')
      end
    end
  end

  describe 'event tracking verification' do
    subject(:execute) { service.execute }

    let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }

    before do
      allow(service).to receive(:update_progress_note)
      allow(service).to receive(:update_review_state)
      allow(progress_note).to receive(:destroy)
    end

    context 'when draft notes are published' do
      let(:draft_note) { instance_double(DraftNote) }
      let(:draft_notes) { [draft_note, draft_note, draft_note] }
      let(:summary) { 'Review summary' }
      let(:process_result) do
        ServiceResponse.success(
          message: summary,
          payload: { draft_notes: draft_notes }
        )
      end

      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)

        allow(Ability).to receive(:allowed?).with(user, :create_note, merge_request).and_return(true)
        allow(DraftNote).to receive(:bulk_insert_and_keep_commits!)
        allow(DraftNotes::PublishService).to receive_message_chain(:new, :execute).and_return({ status: :success })
      end

      it 'tracks comment posting event with correct count' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('post_comment_duo_code_review_on_diff', additional_properties: { value: 3 })
        execute
      end

      it 'does not track no issues event when comments exist' do
        expect(service).not_to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')
        execute
      end
    end

    context 'when no draft notes are created' do
      let(:process_result) do
        ServiceResponse.success(
          message: 'No comments',
          payload: { draft_notes: [] }
        )
      end

      let(:process_service) do
        instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
      end

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_return(process_service)
      end

      it 'tracks no issues found event' do
        expect(service).to receive(:track_review_merge_request_event)
          .with('find_no_issues_duo_code_review_after_review')
        execute
      end

      it 'does not track comment posting event' do
        expect(service).not_to receive(:track_review_merge_request_event)
          .with('post_comment_duo_code_review_on_diff', anything)
        execute
      end
    end

    context 'when the real ProcessCommentsService finds no issues' do
      let(:review_output) { '' }

      it 'tracks the no issues event exactly once' do
        expect { execute }
          .to trigger_internal_events('find_no_issues_duo_code_review_after_review')
          .with(user: user, project: project)
          .once
      end
    end

    context 'when StandardError occurs' do
      let(:error) { StandardError.new('Unexpected error') }

      before do
        allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService)
          .to receive(:new).and_raise(error)

        allow(service).to receive(:track_review_merge_request_exception)
        allow(service).to receive(:track_review_merge_request_event)
      end

      it 'tracks both exception and error event' do
        expect(service).to receive(:track_review_merge_request_exception).with(error)
        expect(service).to receive(:track_review_merge_request_event)
          .with('encounter_duo_code_review_error_during_review')
        execute
      end
    end
  end

  describe 'linking created notes to the workflow' do
    subject(:execute) { service.execute }

    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: project, user: user,
        workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference,
        flow_metadata_json: { flow_id: 'deep_code_review' }.to_json)
    end

    let(:workflow_id) { workflow.id }
    let(:progress_note) { create(:note, noteable: merge_request, project: project) }
    let(:summary) { 'Review summary' }
    let(:draft_notes) do
      [
        build(:draft_note, merge_request: merge_request, author: review_bot, note: 'First comment'),
        build(:draft_note, merge_request: merge_request, author: review_bot, note: 'Second comment')
      ]
    end

    let(:process_result) { ServiceResponse.success(message: summary, payload: { draft_notes: draft_notes }) }
    let(:process_service) do
      instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
    end

    let(:linked_notes) { Ai::DuoWorkflows::WorkflowNote.where(workflow: workflow).link_type_created.map(&:note) }

    before_all do
      project.add_developer(user)
    end

    before do
      allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService).to receive(:new).and_return(process_service)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      stub_ee_application_setting(duo_features_enabled: true)
      allow(user).to receive(:allowed_to_use?).with(:duo_agent_platform, anything).and_return(true)
    end

    it 'links the published review notes, including the summary note, to the workflow' do
      expect(execute).to be_success

      expect(linked_notes.map(&:note)).to contain_exactly('First comment', 'Second comment', summary)
      expect(linked_notes.map(&:author)).to all(eq(review_bot))
    end

    context 'when improved_review_email is disabled' do
      before do
        stub_feature_flags(improved_review_email: false)
      end

      it 'links the published notes and the separate summary note' do
        execute

        expect(linked_notes.map(&:note)).to contain_exactly('First comment', 'Second comment', summary)
      end
    end

    context 'when there are no draft notes' do
      let(:draft_notes) { [] }

      it 'links the progress update note' do
        execute

        expect(linked_notes.map(&:note)).to contain_exactly(summary)
      end
    end

    context 'when the published review cannot be found' do
      before do
        allow_next_instance_of(DraftNotes::PublishService) do |service|
          allow(service).to receive(:execute).and_return({ status: :success, review_id: non_existing_record_id })
        end
      end

      it 'does not link any notes' do
        expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowNote.count }
      end
    end

    context 'when the progress update note fails to save' do
      let(:draft_notes) { [] }

      before do
        allow_next_instance_of(::Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(build(:note, noteable: merge_request, project: project))
        end
      end

      it 'does not link the unsaved note' do
        expect { execute }.not_to change { Ai::DuoWorkflows::WorkflowNote.count }
      end
    end

    context 'when the review posts classified findings' do
      let(:finding) do
        Gitlab::Duo::CodeReview::FindingsParser::Comment.new(
          { 'severity' => 'major', 'category' => 'bug', 'confidence' => 8 }, 'First comment', nil
        )
      end

      let(:process_result) do
        ServiceResponse.success(
          message: summary,
          payload: { draft_notes: draft_notes, comments_by_draft_note: { draft_notes.first => finding } }
        )
      end

      let(:stored_findings) { Ai::DuoWorkflows::CodeReview::Finding.where(merge_request: merge_request) }

      it 'stores the classification of the published note' do
        execute

        expect(stored_findings.sole).to have_attributes(
          note_id: merge_request.notes.find_by(note: 'First comment').id,
          workflow_id: workflow.id,
          severity: 'major',
          category: 'bug'
        )
      end

      context 'when the structured findings flags are disabled' do
        before do
          stub_feature_flags(duo_code_review_deep_flow: false, duo_code_review_standard_structured_findings: false)
        end

        it 'stores nothing' do
          execute

          expect(stored_findings).to be_empty
        end
      end
    end

    shared_examples 'does not link notes' do
      it 'publishes the notes without linking them' do
        expect(execute).to be_success

        expect(merge_request.notes.where(note: ['First comment', 'Second comment', summary]).count).to eq(3)
        expect(Ai::DuoWorkflows::WorkflowNote.count).to eq(0)
      end
    end

    context 'when the user did not start the workflow' do
      let(:workflow_id) do
        create(:duo_workflows_workflow, project: project, user: create(:user),
          workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference).id
      end

      it_behaves_like 'does not link notes'
    end

    context 'when the workflow belongs to another project' do
      let(:workflow_id) do
        create(:duo_workflows_workflow, user: user,
          workflow_definition: Ai::Catalog::FoundationalFlow.code_review_v1.foundational_flow_reference).id
      end

      it_behaves_like 'does not link notes'
    end

    context 'when the workflow is not a code review session' do
      let(:workflow_id) { create(:duo_workflows_workflow, project: project, user: user).id }

      it_behaves_like 'does not link notes'
    end

    context 'when the workflow does not exist' do
      let(:workflow_id) { non_existing_record_id }

      it_behaves_like 'does not link notes'
    end
  end

  describe 'quick actions in review content' do
    subject(:execute) { service.execute }

    let(:progress_note) { create(:note, noteable: merge_request, project: project) }
    let(:comment) { "Looks good.\n/approve\n/merge" }
    let(:summary) { "Summary.\n/approve\n/merge" }
    let(:draft_notes) { [build(:draft_note, merge_request: merge_request, author: review_bot, note: comment)] }
    let(:process_result) { ServiceResponse.success(message: summary, payload: { draft_notes: draft_notes }) }
    let(:process_service) do
      instance_double(Ai::DuoWorkflows::CodeReview::ProcessCommentsService, execute: process_result)
    end

    before_all do
      project.add_developer(user)
    end

    before do
      allow(Ai::DuoWorkflows::CodeReview::ProcessCommentsService).to receive(:new).and_return(process_service)
    end

    it 'posts the commands as literal text without running them' do
      expect(execute).to be_success

      expect(merge_request.notes.authored_by(review_bot).pluck(:note)).to contain_exactly(comment, summary)
      expect(merge_request.approved_by_users.reload).not_to include(review_bot)
    end
  end
end
