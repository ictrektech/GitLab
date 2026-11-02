# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Discussions, feature_category: :team_planning do
  let(:user)         { create(:user) }
  let!(:project)     { create(:project, :public, :repository, namespace: user.namespace) }
  let(:private_user) { create(:user) }

  before do
    project.add_developer(user)
  end

  context 'when noteable is an Epic' do
    let(:group)      { create(:group, :public) }
    let(:epic)       { create(:epic, group: group, author: user) }
    let!(:epic_note) { create(:discussion_note, noteable: epic, project: project, author: user) }

    before do
      group.add_owner(user)
      stub_licensed_features(epics: true)
    end

    it_behaves_like 'discussions API', 'groups', 'epics', 'id', can_reply_to_individual_notes: true do
      let(:parent)   { group }
      let(:noteable) { epic }
      let(:note)     { epic_note }
    end
  end

  describe 'POST /projects/:id/merge_requests/:noteable_id/discussions with quick actions' do
    let(:merge_request) do
      create(:merge_request_with_diffs, source_project: project, target_project: project, author: user)
    end

    let(:position) do
      create(:diff_note_on_merge_request, noteable: merge_request, project: project, author: user)
        .position.to_h.except(:ignore_whitespace_change)
    end

    let(:token) { create(:oauth_access_token, user: user, scopes: [:ai_workflows]) }
    let(:url) { "/projects/#{project.id}/merge_requests/#{merge_request.iid}/discussions" }
    let!(:label) { create(:label, project: project, title: 'bug') }

    def create_discussion(body, extra_params = {})
      post api(url, oauth_access_token: token), params: { body: body }.merge(extra_params)
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      it 'rejects a blocked quick action', :aggregate_failures do
        create_discussion("Comment\n/close")

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('403 Forbidden - Quick actions close cannot be used with AI workflows.')
        expect(merge_request.reset).to be_opened
      end

      it 'rejects a blocked quick action in a diff discussion', :aggregate_failures do
        position

        expect { create_discussion("Comment\n/close", position: position) }.not_to change { Note.count }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(merge_request.reset).to be_opened
      end

      it 'does not run a blocked quick action that acts while it is interpreted', :aggregate_failures do
        pipeline_service = instance_double(MergeRequests::CreatePipelineService, allowed?: true)
        allow(MergeRequests::CreatePipelineService).to receive(:new).and_return(pipeline_service)
        expect(pipeline_service).not_to receive(:execute_async)

        create_discussion("Comment\n/run_pipeline")

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'applies an allowed quick action', :aggregate_failures do
        create_discussion("Comment\n/label ~bug")

        expect(response).to have_gitlab_http_status(:created)
        expect(merge_request.reset.labels).to contain_exactly(label)
      end
    end

    context 'when authenticated with a token that has the api scope' do
      let(:token) { create(:oauth_access_token, user: user, scopes: [:api]) }

      it 'applies the quick action', :aggregate_failures do
        create_discussion("Comment\n/close")

        expect(response).to have_gitlab_http_status(:created)
        expect(merge_request.reset).to be_closed
      end
    end
  end

  describe 'PUT /projects/:id/merge_requests/:noteable_id/discussions/:discussion_id/notes/:note_id' do
    let(:merge_request) { create(:merge_request, source_project: project, author: user) }
    let!(:note) { create(:discussion_note_on_merge_request, noteable: merge_request, project: project, author: user) }
    let!(:label) { create(:label, project: project, title: 'bug') }
    let(:scopes) { [:ai_workflows] }

    def update_note(body)
      token = create(:oauth_access_token, user: user, scopes: scopes)
      url = "/projects/#{project.id}/merge_requests/#{merge_request.iid}" \
        "/discussions/#{note.discussion_id}/notes/#{note.id}"

      put api(url, oauth_access_token: token), params: { body: body }
    end

    context 'with an ai_workflows token' do
      it 'rejects a quick action that is not allowed for AI workflows', :aggregate_failures do
        expect { update_note("Updated\n/close") }.not_to change { note.reload.note }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('403 Forbidden - Quick actions close cannot be used with AI workflows.')
        expect(merge_request.reload).to be_opened
      end

      it 'does not run a quick action that acts while it is interpreted', :aggregate_failures do
        pipeline_service = instance_double(MergeRequests::CreatePipelineService, allowed?: true)
        allow(MergeRequests::CreatePipelineService).to receive(:new).and_return(pipeline_service)
        expect(pipeline_service).not_to receive(:execute_async)

        update_note("Updated\n/run_pipeline")

        expect(response).to have_gitlab_http_status(:forbidden)
      end

      it 'applies an allowed quick action', :aggregate_failures do
        update_note("Updated\n/label ~bug")

        expect(response).to have_gitlab_http_status(:ok)
        expect(merge_request.reload.labels).to contain_exactly(label)
      end
    end

    context 'with an api token' do
      let(:scopes) { [:api] }

      it 'applies the quick action', :aggregate_failures do
        update_note("Updated\n/close")

        expect(response).to have_gitlab_http_status(:ok)
        expect(merge_request.reload).to be_closed
      end
    end
  end
end
