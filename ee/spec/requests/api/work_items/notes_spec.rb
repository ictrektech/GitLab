# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::Notes, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be_with_reload(:epic) { create(:work_item, :epic, namespace: group) }

  let_it_be(:comment) do
    create(:note, namespace: group, project: nil, noteable: epic, author: user, note: 'A user comment on the epic')
  end

  before do
    stub_feature_flags(work_item_rest_api: true)
    stub_licensed_features(epics: true)
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/notes' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/notes" }

    it 'returns notes on the group-level work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(comment.id)
    end

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'with more notes than fit on one page' do
      let_it_be(:extra_notes) do
        create_list(:note, 2, namespace: group, project: nil, noteable: epic, author: user)
      end

      it_behaves_like 'a work item endpoint paginated by cursor'
    end

    context 'with a confidential note between notes a guest can read' do
      let_it_be(:guest) { create(:user, guest_of: group) }
      let_it_be(:author) { create(:user, reporter_of: group) }
      let_it_be(:confidential_note) do
        create(:note, :confidential, namespace: group, project: nil, noteable: epic, author: author)
      end

      let_it_be(:later_note) { create(:note, namespace: group, project: nil, noteable: epic, author: author) }

      let(:user) { guest }
      let(:unreadable_record_id) { confidential_note.id }

      it_behaves_like 'a work item endpoint keeping the cursor on a short page'
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        get api(api_request_path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/notes/:note_id' do
    # Built explicitly rather than by substituting into api_request_path: note ids are small in a
    # fresh database and a substring replace can hit the group id or the iid instead.
    let(:note_path) { ->(note_id) { "/groups/#{group.id}/-/work_items/#{epic.iid}/notes/#{note_id}" } }
    let(:api_request_path) { note_path.call(comment.id) }

    it 'returns the note on the group-level work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to include('id' => comment.id, 'body' => 'A user comment on the epic')
    end

    it 'returns 404 when the note does not exist' do
      get api(note_path.call(non_existing_record_id), user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 when the note belongs to a different epic' do
      other_epic = create(:work_item, :epic, namespace: group)
      other_note = create(:note, namespace: group, project: nil, noteable: other_epic, author: user,
        note: 'A comment on another epic')

      get api(note_path.call(other_note.id), user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns not_found when the feature flag is disabled' do
      stub_feature_flags(work_item_rest_api: false)

      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns unauthorized when no token is provided' do
      get api(api_request_path)

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    context 'with a note the user cannot read' do
      let_it_be(:guest) { create(:user, guest_of: group) }
      let_it_be(:internal_note) do
        create(:note, :confidential, namespace: group, project: nil, noteable: epic, author: user,
          note: 'Internal-only note on the epic')
      end

      it 'returns 404 for a user who cannot read the note', :aggregate_failures do
        # Fetching a readable note first proves the 404 below is about note visibility
        # rather than the guest being unable to reach the epic at all.
        get api(api_request_path, guest)
        expect(response).to have_gitlab_http_status(:ok)

        get api(note_path.call(internal_note.id), guest)
        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns the note for a user who can read it', :aggregate_failures do
        get api(note_path.call(internal_note.id), user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq(internal_note.id)
      end
    end

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        get api(api_request_path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'PUT /groups/:id/-/work_items/:work_item_iid/notes/:note_id' do
    let_it_be_with_reload(:work_item) { epic }

    let(:params) { { body: 'Updated body' } }
    let(:note_path) do
      ->(note_id, work_item_iid: epic.iid) { "/groups/#{group.id}/-/work_items/#{work_item_iid}/notes/#{note_id}" }
    end

    include_context 'for updating a note on a group work item'

    it_behaves_like 'a work item endpoint updating a note'
    it_behaves_like 'a group work item endpoint updating a note'

    it_behaves_like 'authorizing granular token permissions', :update_note do
      let(:boundary_object) { group }
      let(:request) do
        put api(note_path.call(comment.id), personal_access_token: pat), params: params
      end
    end
  end

  describe 'DELETE /groups/:id/-/work_items/:work_item_iid/notes/:note_id' do
    let_it_be_with_reload(:work_item) { epic }

    let(:note_path) do
      ->(note_id, work_item_iid: epic.iid) { "/groups/#{group.id}/-/work_items/#{work_item_iid}/notes/#{note_id}" }
    end

    include_context 'for deleting a note on a group work item'

    it_behaves_like 'a work item endpoint deleting a note'

    it_behaves_like 'authorizing granular token permissions', :delete_note, expected_success_status: :no_content do
      let(:boundary_object) { group }
      let(:request) do
        delete api(note_path.call(comment.id), personal_access_token: pat)
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        expect { delete api(note_path.call(comment.id), user) }.not_to change { Note.exists?(comment.id) }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'POST /groups/:id/-/work_items/:work_item_iid/notes' do
    include_context 'for creating a note on a group work item'

    let_it_be(:non_member) { create(:user) }

    let(:work_item) { epic }
    let(:path_for) { ->(item) { "/groups/#{item.namespace.id}/-/work_items/#{item.iid}/notes" } }

    it_behaves_like 'a work item endpoint creating a note'
    it_behaves_like 'a work item endpoint creating an internal note'
    it_behaves_like 'a work item endpoint rejecting notes on a locked discussion'
    it_behaves_like 'a group work item endpoint creating a note'

    it_behaves_like 'authorizing granular token permissions', :create_note, expected_success_status: :created do
      let(:boundary_object) { group }
      let(:request) do
        post api(api_request_path, personal_access_token: pat), params: params
      end
    end
  end
end
