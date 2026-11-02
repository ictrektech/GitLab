# frozen_string_literal: true

# Provides the group-level setup for 'a work item endpoint updating a note'; callers define `note_path`.
RSpec.shared_context 'for updating a note on a group work item' do
  let_it_be(:non_author) { create(:user, developer_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:quick_action_label) { create(:group_label, group: group, title: 'bug') }
  let_it_be(:system_note) do
    create(:note, :system, namespace: group, project: nil, noteable: work_item, author: user, note: 'changed the title')
  end

  let_it_be(:internal_note) do
    create(:note, :confidential, namespace: group, project: nil, noteable: work_item, author: user,
      note: 'Internal-only note')
  end

  let_it_be(:other_work_item) { create(:work_item, :epic, namespace: group) }
  let_it_be(:other_note) do
    create(:note, namespace: group, project: nil, noteable: other_work_item, author: user,
      note: 'Note on another work item')
  end
end

# Requires `comment`, `user`, `work_item`, `note_path` and `params` from the caller.
RSpec.shared_examples 'a group work item endpoint updating a note' do
  context 'when the note is edited to add a quick action' do
    let(:token) { create(:oauth_access_token, user: user, scopes: [:ai_workflows]) }

    def update_comment(body)
      put api(note_path.call(comment.id), oauth_access_token: token), params: { body: body }
    end

    context 'with an ai_workflows token' do
      it 'rejects a quick action that is not allowed for AI workflows', :aggregate_failures do
        expect { update_comment("Updated\n/close") }.not_to change { [comment.reload.note, work_item.reload.state] }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to eq('403 Forbidden - Quick actions close cannot be used with AI workflows.')
      end

      it 'applies an allowed quick action', :aggregate_failures do
        update_comment("Updated\n/label ~#{quick_action_label.title}")

        expect(response).to have_gitlab_http_status(:ok)
        expect(work_item.reload.labels).to include(quick_action_label)
      end
    end

    context 'with an api token' do
      let(:token) { create(:oauth_access_token, user: user, scopes: [:api]) }

      it 'does not check the quick action' do
        update_comment("Updated\n/close")

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  context 'without the epics license' do
    before do
      stub_licensed_features(epics: false)
    end

    it 'returns 404 when the parent is not readable' do
      expect { put api(note_path.call(comment.id), user), params: params }.not_to change { comment.reload.note }

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
