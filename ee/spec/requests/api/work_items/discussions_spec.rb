# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::Discussions, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  # Creating a note touches the noteable, which fails on a frozen record once it is over a minute old.
  let_it_be_with_reload(:epic) { create(:work_item, :epic, namespace: group) }

  let_it_be(:comment) do
    create(:note, namespace: group, project: nil, noteable: epic, author: user, note: 'A user comment on the epic')
  end

  let_it_be(:system_note) do
    create(:note, :system, namespace: group, project: nil, noteable: epic, author: user, note: 'changed the title')
  end

  let(:work_item) { epic }
  let(:container) { group }
  let(:note_params) { { namespace: group, project: nil } }

  before do
    stub_feature_flags(work_item_rest_api: true)
    stub_licensed_features(epics: true)
  end

  shared_examples 'a group work item endpoint resolving a discussion' do
    let_it_be(:discussion_note, reload: true) do
      create(:discussion_note_on_work_item, noteable: epic, author: user, namespace: group, project: nil)
    end

    it_behaves_like 'a work item endpoint resolving a discussion'

    it_behaves_like 'authorizing granular token permissions', :update_issue_discussion do
      let(:boundary_object) { group }
      let(:request) do
        put api(api_request_path, personal_access_token: pat), params: { resolved: true }
      end
    end

    it 'returns not_found when the user cannot read the work item' do
      put api(api_request_path, non_member), params: { resolved: true }

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/discussions" }

    it_behaves_like 'a work item discussions endpoint'

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'with a confidential discussion between discussions a guest can read' do
      let_it_be(:guest) { create(:user, guest_of: group) }
      let_it_be(:author) { create(:user, reporter_of: group) }
      let_it_be(:confidential_note) do
        create(:note, :confidential, namespace: group, project: nil, noteable: epic, author: author)
      end

      let_it_be(:later_note) { create(:note, namespace: group, project: nil, noteable: epic, author: author) }

      let(:user) { guest }
      let(:unreadable_record_id) { confidential_note.discussion_id }

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

    it 'returns not_found when the user cannot read the work item' do
      get api(api_request_path, non_member)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/discussions/#{comment.discussion_id}" }

    it_behaves_like 'a work item single discussion endpoint'

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

    it 'returns not_found when the user cannot read the work item' do
      get api(api_request_path, non_member)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'POST /namespaces/:id/-/work_items/:work_item_iid/discussions' do
    include_context 'for creating a note on a group work item'

    let(:path_for) do
      ->(item) { "/namespaces/#{CGI.escape(item.namespace.full_path)}/-/work_items/#{item.iid}/discussions" }
    end

    it_behaves_like 'a group work item endpoint creating a note' do
      let(:created_note_json) { json_response['notes'].first }
    end

    it 'creates a new discussion thread on the epic', :aggregate_failures do
      post api(api_request_path, user), params: params

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response['individual_note']).to be(false)
      expect(json_response['notes'].first['type']).to eq('DiscussionNote')
    end

    it_behaves_like 'authorizing granular token permissions', :create_note, expected_success_status: :created do
      let(:boundary_object) { group }
      let(:request) do
        post api(api_request_path, personal_access_token: pat), params: params
      end
    end
  end

  describe 'POST /groups/:id/-/work_items/:work_item_iid/discussions' do
    include_context 'for creating a note on a group work item'

    let(:path_for) { ->(item) { "/groups/#{item.namespace.id}/-/work_items/#{item.iid}/discussions" } }

    it_behaves_like 'a work item endpoint creating a discussion'
    it_behaves_like 'a group work item endpoint creating a note' do
      let(:created_note_json) { json_response['notes'].first }
    end

    it_behaves_like 'authorizing granular token permissions', :create_note, expected_success_status: :created do
      let(:boundary_object) { group }
      let(:request) do
        post api(api_request_path, personal_access_token: pat), params: params
      end
    end
  end

  describe 'PUT /namespaces/:id/-/work_items/:work_item_iid/discussions/:discussion_id' do
    let(:api_request_path) do
      "/namespaces/#{CGI.escape(group.full_path)}/-/work_items/#{epic.iid}/discussions/#{discussion_note.discussion_id}"
    end

    it_behaves_like 'a group work item endpoint resolving a discussion'
  end

  describe 'PUT /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id' do
    let(:api_request_path) do
      "/groups/#{group.id}/-/work_items/#{epic.iid}/discussions/#{discussion_note.discussion_id}"
    end

    it_behaves_like 'a group work item endpoint resolving a discussion'
  end
end
