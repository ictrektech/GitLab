# frozen_string_literal: true

# Provides the group-level setup for 'a work item endpoint creating a note'; callers define `path_for`.
RSpec.shared_context 'for creating a note on a group work item' do
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:public_group) { create(:group, :public) }
  let_it_be(:locked_work_item) { create(:work_item, :epic, namespace: public_group, discussion_locked: true) }
  let_it_be(:quick_action_label) { create(:group_label, group: group, title: 'bug') }

  let(:api_request_path) { path_for.call(work_item) }
  let(:params) { { body: 'hi!' } }
end

# Requires `group`, `user`, `work_item`, `api_request_path` and `params` from the caller.
# May be overridden by the caller:
#   created_note_json  - the created note in the response, when it is nested (e.g. in a discussion)
RSpec.shared_examples 'a group work item endpoint creating a note' do
  let(:created_note_json) { json_response }

  it 'stores the note against the group', :aggregate_failures do
    post api(api_request_path, user), params: params

    expect(response).to have_gitlab_http_status(:created)
    expect(created_note_json['project_id']).to be_nil
    expect(Note.find(created_note_json['id']).namespace_id).to eq(group.id)
  end

  context 'when an ai_workflows token uses a quick action that is not allowed for AI workflows' do
    let_it_be(:oauth_token) { create(:oauth_access_token, user: user, scopes: [:api, :ai_workflows]) }

    it 'returns forbidden with the reason', :aggregate_failures do
      expect { post api(api_request_path, oauth_access_token: oauth_token), params: { body: '/close' } }
        .not_to change { work_item.reload.state }

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to include('Quick actions close cannot be used with AI workflows')
    end
  end

  context 'without the epics license' do
    before do
      stub_licensed_features(epics: false)
    end

    it 'returns 404 when the parent is not readable' do
      post api(api_request_path, user), params: params

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
