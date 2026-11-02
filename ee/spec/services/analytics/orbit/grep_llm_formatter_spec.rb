# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::GrepLlmFormatter, feature_category: :knowledge_graph do
  subject(:text) { described_class.new(grep).execute }

  let(:grep) do
    {
      version: '1.1.0',
      request: { search: "search\nterm", limit: 20, per_scope: 5 },
      target: { type: 'Project', id: 1, token: 'Project[1]', full_path: 'group/project' },
      result_count: 4,
      scopes: [
        { name: 'merge_requests', status: 'ok', backend: 'basic', result_count: 1, pagination: { has_more: false } },
        { name: 'blobs', status: 'ok', backend: 'basic', result_count: 1, pagination: { has_more: false } },
        { name: 'notes', status: 'unavailable', reason: { code: 'not_available_for_search_type' } },
        { name: 'users', status: 'skipped', reason: { code: 'limit_reached' } }
      ],
      results: [
        {
          scope: 'merge_requests', type: 'MergeRequest', id: 2, token: 'MergeRequest[2]',
          reference: { id: 2, iid: 7, project_path: 'group/project' }, text: "Add\ngrep", state: 'merged'
        },
        {
          scope: 'blobs', type: 'File', id: nil, token: nil,
          reference: { project_id: 1, project_path: 'group/project', path: 'README.md', branch: 'master',
                       commit_sha: nil },
          text: 'README.md'
        },
        {
          scope: 'notes', type: 'Note', id: 3, token: 'Note[3]',
          reference: { id: 3, noteable: 'MergeRequest[2]', noteable_reference: 'group/project!7' }, text: 'LGTM'
        },
        {
          scope: 'users', type: 'User', id: 4, token: 'User[4]', reference: { id: 4 }, text: 'root Administrator'
        }
      ],
      truncated: false
    }
  end

  it 'formats line-oriented output and quotes untrusted values' do
    expect(text.lines).to eq([
      "orbit_grep version=1.1.0 target=Project[1] search=\"search\\nterm\" " \
        "scopes=\"merge_requests,blobs,notes,users\" results=4 truncated=false\n",
      "- MergeRequest[2] type=MergeRequest iid=\"7\" project_path=\"group/project\" state=\"merged\" " \
        "text=\"Add\\ngrep\"\n",
      "- File project_id=\"1\" project_path=\"group/project\" path=\"README.md\" branch=\"master\" type=File " \
        "text=\"README.md\"\n",
      "- Note[3] type=Note noteable=\"MergeRequest[2]\" noteable_reference=\"group/project!7\" text=\"LGTM\"\n",
      "- User[4] type=User text=\"root Administrator\"\n",
      "! unavailable scope=notes reason=not_available_for_search_type\n",
      "! skipped scope=users reason=limit_reached\n"
    ])
  end
end
