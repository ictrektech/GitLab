# frozen_string_literal: true

# Provides the group-level setup for 'a work item endpoint deleting a note'; callers define `note_path`.
RSpec.shared_context 'for deleting a note on a group work item' do
  let_it_be(:non_author) { create(:user, developer_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }
  let_it_be(:non_member) { create(:user) }
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

  let_it_be(:other_group) { create(:group, :private, reporters: user) }
  let_it_be(:other_parent_work_item) { create(:work_item, :epic, namespace: other_group) }
  let_it_be(:other_parent_note) do
    create(:note, namespace: other_group, project: nil, noteable: other_parent_work_item, author: user,
      note: 'Note elsewhere')
  end
end
