# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::DiscussionNotes, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be_with_reload(:epic) { create(:work_item, :epic, namespace: group) }

  let_it_be(:comment) do
    create(:note, namespace: group, project: nil, noteable: epic, author: user, note: 'A user comment on the epic')
  end

  let(:work_item) { epic }
  let(:container) { group }
  let(:note_params) { { namespace: group, project: nil } }

  let(:discussion_note_path) do
    ->(discussion_id, note_id, work_item_iid: epic.iid) do
      "#{work_items_path}/#{work_item_iid}/discussions/#{discussion_id}/notes/#{note_id}"
    end
  end

  before do
    stub_licensed_features(epics: true)
  end

  # `request_for` is a lambda taking the same arguments as the `api` helper.
  shared_examples 'a group work item endpoint guarding access' do |permission, **token_options|
    it_behaves_like 'authorizing granular token permissions', permission, **token_options do
      let(:boundary_object) { group }
      let(:request) { request_for.call(personal_access_token: pat) }
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        request_for.call(user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    it 'returns not_found when the user cannot read the work item' do
      request_for.call(non_member)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples 'a group work item discussion notes endpoint' do
    let(:api_request_path) { "#{work_items_path}/#{epic.iid}/discussions/#{comment.discussion_id}/notes" }
    let(:request_for) { ->(*args, **opts) { get api(api_request_path, *args, **opts) } }

    it_behaves_like 'a work item discussion notes endpoint'
    it_behaves_like 'a group work item endpoint guarding access', :read_work_item
  end

  shared_examples 'a group work item endpoint replying to a discussion' do
    let(:api_request_path) { reply_path.call(epic, comment.discussion_id) }

    it_behaves_like 'a work item endpoint replying to a discussion'
    it_behaves_like 'a group work item endpoint creating a note'

    it_behaves_like 'authorizing granular token permissions', :create_note, expected_success_status: :created do
      let(:boundary_object) { group }
      let(:request) do
        post api(api_request_path, personal_access_token: pat), params: params
      end
    end
  end

  shared_examples 'a group work item discussion note endpoint' do
    let(:api_request_path) { discussion_note_path.call(comment.discussion_id, comment.id) }
    let(:request_for) { ->(*args, **opts) { get api(api_request_path, *args, **opts) } }

    it_behaves_like 'a work item discussion note endpoint'
    it_behaves_like 'a group work item endpoint guarding access', :read_work_item
  end

  shared_examples 'a group work item endpoint updating a discussion note' do
    let(:discussion_note) { create(:discussion_note_on_work_item, noteable: epic, author: user, **note_params) }
    let(:api_request_path) { discussion_note_path.call(discussion_note.discussion_id, discussion_note.id) }
    let(:request_for) do
      ->(*args, **opts) { put api(api_request_path, *args, **opts), params: { body: 'Hello!' } }
    end

    it_behaves_like 'a work item endpoint updating a discussion note'
    it_behaves_like 'a group work item endpoint guarding access', :update_issue_discussion_note
  end

  shared_examples 'a group work item endpoint deleting a discussion note' do
    let(:deletable_note) { create(:discussion_note_on_work_item, noteable: epic, author: user, **note_params) }
    let(:api_request_path) { discussion_note_path.call(deletable_note.discussion_id, deletable_note.id) }
    let(:request_for) { ->(*args, **opts) { delete api(api_request_path, *args, **opts) } }

    it_behaves_like 'a work item endpoint deleting a discussion note'
    it_behaves_like 'a group work item endpoint guarding access', :delete_note, expected_success_status: :no_content
  end

  context 'with the group path' do
    let(:work_items_path) { "/groups/#{group.id}/-/work_items" }

    describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes' do
      it_behaves_like 'a group work item discussion notes endpoint'
    end

    describe 'POST /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes' do
      include_context 'for creating a note on a group work item'

      let(:reply_path) do
        ->(item, discussion_id) do
          "/groups/#{item.namespace.id}/-/work_items/#{item.iid}/discussions/#{discussion_id}/notes"
        end
      end

      it_behaves_like 'a group work item endpoint replying to a discussion'
      it_behaves_like 'a work item endpoint rejecting replies to a locked discussion'
    end

    describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item discussion note endpoint'
    end

    describe 'PUT /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item endpoint updating a discussion note'
    end

    describe 'DELETE /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item endpoint deleting a discussion note'
    end
  end

  context 'with the namespace path' do
    let(:work_items_path) { "/namespaces/#{CGI.escape(group.full_path)}/-/work_items" }

    describe 'GET /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes' do
      it_behaves_like 'a group work item discussion notes endpoint'
    end

    describe 'POST /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes' do
      include_context 'for creating a note on a group work item'

      let(:reply_path) do
        ->(item, discussion_id) do
          "/namespaces/#{CGI.escape(item.namespace.full_path)}/-/work_items/#{item.iid}/discussions/" \
            "#{discussion_id}/notes"
        end
      end

      it_behaves_like 'a group work item endpoint replying to a discussion'
    end

    describe 'GET /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item discussion note endpoint'
    end

    describe 'PUT /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item endpoint updating a discussion note'
    end

    describe 'DELETE /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id/notes/:note_id' do
      it_behaves_like 'a group work item endpoint deleting a discussion note'
    end
  end
end
