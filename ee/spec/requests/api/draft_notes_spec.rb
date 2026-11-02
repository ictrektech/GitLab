# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::DraftNotes, feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository, developers: user) }
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, target_project: project, author: user)
  end

  let_it_be(:base_url) { "/projects/#{project.id}/merge_requests/#{merge_request.iid}/draft_notes" }

  describe "Bulk publishing draft notes with reviewer_state" do
    before do
      stub_licensed_features(requested_changes_block_merge_request: true)
      merge_request.reviewers << user
    end

    let!(:draft_note) { create(:draft_note, merge_request: merge_request, author: user) }

    context "when the caller has previously requested changes" do
      before do
        create(:merge_request_requested_changes, merge_request: merge_request, project: project, user: user)
      end

      it "clears the requested changes when reviewer_state is 'reviewed'", :aggregate_failures do
        expect(merge_request.reset.has_changes_requested?).to be(true)

        post api("#{base_url}/bulk_publish", user), params: { reviewer_state: 'reviewed' }

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.has_changes_requested?).to be(false)

        reviewer = merge_request.merge_request_reviewers.find_by(user_id: user.id)
        expect(reviewer.state).to eq('reviewed')
      end

      it "keeps the requested changes when reviewer_state is 'requested_changes'", :aggregate_failures do
        post api("#{base_url}/bulk_publish", user), params: { reviewer_state: 'requested_changes' }

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.has_changes_requested?).to be(true)

        reviewer = merge_request.merge_request_reviewers.find_by(user_id: user.id)
        expect(reviewer.state).to eq('requested_changes')
      end

      it "records no formal approval when clearing via 'reviewed'" do
        expect do
          post api("#{base_url}/bulk_publish", user), params: { reviewer_state: 'reviewed' }
        end.not_to change { merge_request.approvals.count }
      end
    end

    context "when the caller has no prior requested changes" do
      it "is a harmless no-op and still sets the reviewer state", :aggregate_failures do
        expect(merge_request.reset.has_changes_requested?).to be(false)

        post api("#{base_url}/bulk_publish", user), params: { reviewer_state: 'reviewed' }

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.has_changes_requested?).to be(false)

        reviewer = merge_request.merge_request_reviewers.find_by(user_id: user.id)
        expect(reviewer.state).to eq('reviewed')
      end
    end

    context "when the requested_changes feature is unavailable" do
      before do
        stub_licensed_features(requested_changes_block_merge_request: false)
        create(:merge_request_requested_changes, merge_request: merge_request, project: project, user: user)
      end

      it "does not clear the requested changes and still sets the reviewer state", :aggregate_failures do
        post api("#{base_url}/bulk_publish", user), params: { reviewer_state: 'reviewed' }

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.has_changes_requested?).to be(true)
        reviewer = merge_request.merge_request_reviewers.find_by(user_id: user.id)
        expect(reviewer.state).to eq('reviewed')
      end
    end
  end

  describe "Publishing draft notes with quick actions" do
    let_it_be(:label) { create(:label, project: project, title: 'bug') }

    let(:token) { create(:oauth_access_token, user: user, scopes: [:ai_workflows]) }
    let(:blocked_message) { '403 Forbidden - Quick actions close cannot be used with AI workflows.' }

    def bulk_publish(params = {})
      post api("#{base_url}/bulk_publish", oauth_access_token: token), params: params
    end

    context "when authenticated with a token that has the ai_workflows scope" do
      it "rejects a blocked quick action in the summary note", :aggregate_failures do
        bulk_publish(note: "Summary\n/close")

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq(blocked_message)
        expect(merge_request.reset).to be_opened
      end

      it "applies an allowed quick action in the summary note", :aggregate_failures do
        bulk_publish(note: "Summary\n/label ~bug")

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.labels).to contain_exactly(label)
      end

      it "accepts a summary note that is only an allowed quick action", :aggregate_failures do
        bulk_publish(note: "/label ~bug")

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset.labels).to contain_exactly(label)
      end

      it "returns the error when the summary note is not saved", :aggregate_failures do
        unsaved_note = build(:note, noteable: merge_request, project: project)
        unsaved_note.errors.add(:base, 'Summary not saved')
        allow_next_instance_of(Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(unsaved_note)
        end

        bulk_publish(note: 'Summary')

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to eq('Summary not saved')
      end

      it "returns the quick action errors when the summary note only has failed commands", :aggregate_failures do
        unsaved_note = build(:note, noteable: merge_request, project: project)
        unsaved_note.quick_actions_status =
          Notes::QuickActionsStatus.new(command_names: [:label], commands_only: true).tap do |status|
            status.add_error('Could not apply label command')
          end
        allow_next_instance_of(Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(unsaved_note)
        end

        bulk_publish(note: '/label ~bug')

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to eq('Could not apply label command')
      end

      it "returns an error when the summary note is not saved and has no quick action status" do
        unsaved_note = build(:note, noteable: merge_request, project: project)
        allow_next_instance_of(Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(unsaved_note)
        end

        bulk_publish(note: 'Summary')

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
      end

      it "rejects a blocked summary note before publishing any draft note", :aggregate_failures do
        draft_note = create(:draft_note, merge_request: merge_request, author: user, note: 'Looks good')

        expect { bulk_publish(note: "Summary\n/close") }.not_to change { [Note.count, Review.count] }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(DraftNote.exists?(draft_note.id)).to be(true)
      end

      it "rejects a batch with a blocked draft note before publishing any of them", :aggregate_failures do
        create(:draft_note, merge_request: merge_request, author: user, note: 'Looks good')
        create(:draft_note, merge_request: merge_request, author: user, note: "Done\n/close")

        expect { bulk_publish }.not_to change { [Note.count, Review.count, DraftNote.count] }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq(blocked_message)
      end

      it "does not run a blocked quick action that acts while it is interpreted", :aggregate_failures do
        pipeline_service = instance_double(MergeRequests::CreatePipelineService, allowed?: true)
        allow(MergeRequests::CreatePipelineService).to receive(:new).and_return(pipeline_service)
        expect(pipeline_service).not_to receive(:execute_async)

        create(:draft_note, merge_request: merge_request, author: user, note: "Done\n/run_pipeline")

        expect { bulk_publish }.not_to change { Note.count }

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      context "when a draft note contains a blocked quick action" do
        let!(:draft_note) { create(:draft_note, merge_request: merge_request, author: user, note: "Done\n/close") }

        it "rejects publishing all draft notes", :aggregate_failures do
          bulk_publish

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to eq(blocked_message)
          expect(merge_request.reset).to be_opened
          expect(DraftNote.exists?(draft_note.id)).to be(true)
        end

        it "rejects publishing the draft note", :aggregate_failures do
          put api("#{base_url}/#{draft_note.id}/publish", oauth_access_token: token)

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to eq(blocked_message)
          expect(merge_request.reset).to be_opened
          expect(DraftNote.exists?(draft_note.id)).to be(true)
        end
      end
    end

    context "when authenticated with a token that has the api scope" do
      let(:token) { create(:oauth_access_token, user: user, scopes: [:api]) }

      it "applies the quick action in the summary note", :aggregate_failures do
        bulk_publish(note: "Summary\n/close")

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset).to be_closed
      end

      it "applies the quick action in a draft note", :aggregate_failures do
        draft_note = create(:draft_note, merge_request: merge_request, author: user, note: "Done\n/close")

        put api("#{base_url}/#{draft_note.id}/publish", oauth_access_token: token)

        expect(response).to have_gitlab_http_status(:no_content)
        expect(merge_request.reset).to be_closed
      end
    end
  end
end
