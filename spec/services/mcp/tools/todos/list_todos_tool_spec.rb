# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Todos::ListTodosTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:author) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:other_project) { create(:project, :public) }
  let_it_be(:issue) { create(:issue, project: project) }
  let_it_be(:other_issue) { create(:issue, project: other_project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let_it_be(:assigned_todo) do
    create(:todo, :assigned, user: user, author: author, project: project, target: issue)
  end

  let_it_be(:review_todo) do
    create(:todo, :review_requested, user: user, author: user, project: project, target: merge_request)
  end

  let_it_be(:done_todo) do
    create(:todo, :mentioned, :done, user: user, author: author, project: other_project, target: other_issue)
  end

  let_it_be(:other_users_todo) { create(:todo, user: author, author: user, project: project, target: issue) }

  let(:params) { {} }
  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }

  def result_ids(result)
    result[:structuredContent]['nodes'].pluck('id')
  end

  describe 'versioning' do
    it 'registers version 0.1.0' do
      expect(tool.version).to eq(Mcp::Tools::Concerns::Constants::VERSIONS[:v0_1_0])
    end

    it 'reads the currentUser root field' do
      expect(tool.operation_name).to eq('currentUser')
    end
  end

  describe '#build_variables' do
    it 'applies the default page size and no filters' do
      expect(tool.build_variables).to eq(first: 20)
    end

    context 'with filters and pagination' do
      let(:params) do
        {
          state: 'done',
          action: 'mentioned',
          type: 'ISSUE',
          author_id: author.id,
          project_id: project.full_path,
          group_id: group.id.to_s,
          first: 5,
          after: 'cursor'
        }
      end

      it 'maps them to GraphQL variables, resolving the project and group to numeric IDs' do
        expect(tool.build_variables).to eq(
          state: ['done'],
          action: ['mentioned'],
          type: ['ISSUE'],
          authorId: [author.id.to_s],
          projectId: [project.id.to_s],
          groupId: [group.id.to_s],
          first: 5,
          after: 'cursor'
        )
      end
    end
  end

  describe '#execute' do
    it 'returns the pending to-do items of the current user' do
      expect(result_ids(tool.execute)).to contain_exactly(assigned_todo.id, review_todo.id)
    end

    it 'returns numeric IDs and the target, author, and project of each to-do item', :aggregate_failures do
      result = tool.execute

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent]['pageInfo']).to include('hasNextPage' => false)

      todo = result[:structuredContent]['nodes'].find { |node| node['id'] == assigned_todo.id }
      expect(todo).to include(
        'action' => 'assigned',
        'state' => 'pending',
        'targetType' => 'ISSUE',
        'targetUrl' => assigned_todo.target_url,
        'author' => include('id' => author.id, 'username' => author.username),
        'project' => include('id' => project.id, 'fullPath' => project.full_path),
        'group' => nil
      )
      expect(todo['targetEntity']).to include('name' => issue.title, 'iid' => issue.iid.to_s)
    end

    context 'with state done' do
      let(:params) { { state: 'done' } }

      it 'returns only done to-do items' do
        expect(result_ids(tool.execute)).to contain_exactly(done_todo.id)
      end
    end

    context 'with an action' do
      let(:params) { { action: 'review_requested' } }

      it 'returns only to-do items created by that action' do
        expect(result_ids(tool.execute)).to contain_exactly(review_todo.id)
      end
    end

    context 'with a target type' do
      let(:params) { { type: 'MERGEREQUEST' } }

      it 'returns only to-do items on that type of target' do
        expect(result_ids(tool.execute)).to contain_exactly(review_todo.id)
      end
    end

    context 'with an author' do
      let(:params) { { author_id: author.id } }

      it 'returns only to-do items created by that user' do
        expect(result_ids(tool.execute)).to contain_exactly(assigned_todo.id)
      end
    end

    context 'with a project full path' do
      let(:params) { { project_id: other_project.full_path, state: 'done' } }

      it 'returns only to-do items in that project' do
        expect(result_ids(tool.execute)).to contain_exactly(done_todo.id)
      end
    end

    context 'with a group' do
      let(:params) { { group_id: group.full_path } }

      it 'returns only to-do items in projects of that group' do
        expect(result_ids(tool.execute)).to contain_exactly(assigned_todo.id, review_todo.id)
      end
    end

    context 'with a group to-do item' do
      let_it_be(:group_todo) do
        create(:todo, :member_access_requested, user: user, author: author, group: group, target: group)
      end

      it 'returns the numeric group ID and no project' do
        todo = tool.execute[:structuredContent]['nodes'].find { |node| node['id'] == group_todo.id }

        expect(todo).to include('project' => nil, 'group' => include('id' => group.id, 'fullPath' => group.full_path))
      end
    end

    context 'with a malformed cursor' do
      let(:params) { { after: 'not-a-cursor' } }

      it 'returns the GraphQL error', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Please provide a valid cursor')
      end
    end
  end
end
