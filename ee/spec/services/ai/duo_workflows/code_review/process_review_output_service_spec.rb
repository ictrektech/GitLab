# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::ProcessReviewOutputService, feature_category: :dap_code_review do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be_with_refind(:merge_request) { create(:merge_request, source_project: project) }

  let(:review_output) { '<review></review>' }
  let(:workflow_id) { 99 }

  let(:service) do
    described_class.new(
      user: user,
      project: project,
      merge_request: merge_request,
      review_output: review_output,
      workflow_id: workflow_id
    )
  end

  describe '#valid?' do
    context 'when review_output is blank' do
      where(:blank_value) { [nil, ''] }

      with_them do
        let(:review_output) { blank_value }

        it 'returns false without checking diff files' do
          expect(merge_request).not_to receive(:merge_request_diff)
          expect(merge_request).not_to receive(:ai_reviewable_diff_files)

          expect(service.valid?).to be(false)
        end

        it 'sets message to the invalid_review_output text' do
          service.valid?

          expect(service.message).to include(::Gitlab::Duo::CodeReview::Messages.invalid_review_output)
        end
      end
    end

    context 'when the first diff batch has no reviewable file' do
      before do
        allow_next_instance_of(Gitlab::Diff::FileCollection::MergeRequestDiffBatch) do |batch|
          allow(batch).to receive(:raw_diff_files).and_return([])
        end
      end

      context 'when review_output is present but there are no reviewable diff files' do
        before do
          allow(merge_request).to receive(:ai_reviewable_diff_files).and_return([])
          allow(merge_request).to receive_message_chain(:diffs, :diff_file_paths).and_return([])
        end

        it 'returns false' do
          expect(service.valid?).to be(false)
        end

        it 'sets message to the nothing_to_review text' do
          service.valid?

          expect(service.message).to include(::Gitlab::Duo::CodeReview::Messages.nothing_to_review)
        end
      end

      context 'when there are reviewable diff files and review_output is present' do
        before do
          allow(merge_request).to receive(:ai_reviewable_diff_files)
            .and_return([instance_double(Gitlab::Diff::File, file_path: 'a.rb')])
          allow(merge_request).to receive_message_chain(:diffs, :diff_file_paths).and_return([])
        end

        it 'returns true' do
          expect(service.valid?).to be(true)
        end

        it 'leaves message nil' do
          service.valid?

          expect(service.message).to be_nil
        end
      end

      it 'is memoized — computed only once' do
        allow(merge_request).to receive(:ai_reviewable_diff_files)
          .and_return([instance_double(Gitlab::Diff::File, file_path: 'a.rb')])
        allow(merge_request).to receive_message_chain(:diffs, :diff_file_paths).and_return([])

        service.valid?
        service.valid?

        expect(merge_request).to have_received(:ai_reviewable_diff_files).once
      end

      describe 'blob loading' do
        before do
          allow(merge_request).to receive(:ai_reviewable_diff_files)
            .and_return([instance_double(Gitlab::Diff::File, file_path: 'a.rb')])
          allow(merge_request).to receive_message_chain(:diffs, :diff_file_paths).and_return([])
        end

        it 'selects reviewable files from the patch alone' do
          service.valid?

          expect(merge_request).to have_received(:ai_reviewable_diff_files).with(patch_only: true)
        end
      end
    end

    context 'with real diffs' do
      def stub_exclusions(excluded)
        exclusion_service = instance_double(::Ai::FileExclusionService)
        allow(::Ai::FileExclusionService).to receive(:new).with(project).and_return(exclusion_service)
        allow(exclusion_service).to receive(:execute) do |paths|
          ServiceResponse.success(payload: paths.map { |path| { path: path, excluded: excluded.call(path) } })
        end
      end

      context 'when the first diff batch has a reviewable file' do
        it 'returns true without loading the full diff collection' do
          expect(merge_request).not_to receive(:diffs)
          expect(merge_request).not_to receive(:ai_reviewable_diff_files)

          expect(service.valid?).to be(true)
        end
      end

      context 'when every reviewable file in the first diff batch is excluded' do
        before do
          stub_const('Ai::DuoWorkflows::CodeReview::FileExclusion::FIRST_DIFF_BATCH_SIZE', 1)

          first_path = merge_request.diffs(expanded: true).diff_file_paths.first
          stub_exclusions(->(path) { path == first_path })
        end

        it 'falls back to the full diff collection' do
          expect(merge_request).to receive(:ai_reviewable_diff_files).and_call_original

          expect(service.valid?).to be(true)
        end
      end

      context 'when every file is excluded' do
        before do
          stub_exclusions(->(_path) { true })
        end

        it 'loads the full diff collection once, excludes by the same path and lists the excluded files' do
          # One collection for the first batch, one for the full check shared by both lookups.
          expect(Gitlab::Git::DiffCollection).to receive(:new).twice.and_call_original

          expect(service.valid?).to be(false)
          expect(service.message).to include('* CHANGELOG', ::Gitlab::Duo::CodeReview::Messages.nothing_to_review)
        end
      end
    end
  end

  describe '#execute' do
    let(:progress_note) { create(:note, noteable: merge_request, project: merge_request.project) }

    before do
      allow(merge_request).to receive(:duo_code_reviewed?).and_return(false)
      allow(service).to receive(:find_or_create_progress_note).and_return(progress_note)
      allow(Ai::DuoWorkflows::CodeReview::PublishCommentsWorker).to receive(:perform_async)
    end

    it 'enqueues PublishCommentsWorker with progress_note_id as positional arg' do
      expect(Ai::DuoWorkflows::CodeReview::PublishCommentsWorker)
        .to receive(:perform_async)
        .with(
          workflow_id,
          merge_request.id,
          user.id,
          progress_note.id,
          review_output
        )

      service.execute
    end

    it 'returns a success ServiceResponse' do
      expect(service.execute).to be_success
    end

    context 'when the review is already completed' do
      before do
        allow(merge_request).to receive(:duo_code_reviewed?).and_return(true)
      end

      it 'returns success silently without enqueueing a worker' do
        expect(Ai::DuoWorkflows::CodeReview::PublishCommentsWorker).not_to receive(:perform_async)

        expect(service.execute).to be_success
      end

      it 'does not attempt to create a progress note' do
        expect(service).not_to receive(:find_or_create_progress_note)

        service.execute
      end
    end

    context 'when progress note cannot be found or created' do
      before do
        allow(service).to receive(:find_or_create_progress_note).and_return(nil)
      end

      it 'returns an error without enqueueing the worker' do
        expect(Ai::DuoWorkflows::CodeReview::PublishCommentsWorker).not_to receive(:perform_async)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to match(/Can't create the progress note/)
      end
    end

    context 'without a workflow_id' do
      let(:service) do
        described_class.new(user: user, project: project, merge_request: merge_request, review_output: review_output)
      end

      it 'enqueues the worker with nil workflow_id' do
        expect(Ai::DuoWorkflows::CodeReview::PublishCommentsWorker)
          .to receive(:perform_async)
          .with(nil, merge_request.id, user.id, progress_note.id, review_output)

        service.execute
      end
    end
  end
end
