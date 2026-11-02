# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::ListWorkItemsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:project) { create(:project, :public, group: group) }

  let(:service) { described_class.new(name: 'list_work_items') }
  let(:request) { instance_double(ActionDispatch::Request) }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(service.input_schema).to eq({
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'GitLab URL for the project or group.'
          },
          group_id: {
            type: 'string',
            description: 'ID or path of the group. Required if URL and project_id are not provided.'
          },
          project_id: {
            type: 'string',
            description: 'ID or path of the project. Required if URL and group_id are not provided.'
          },
          state: {
            type: 'string',
            enum: %w[opened closed all],
            description: 'Filter by state.'
          },
          search: {
            type: 'string',
            description: 'Free-text search in title and description.'
          },
          author_username: {
            type: 'string',
            description: 'Username of the author.'
          },
          assignee_usernames: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Usernames of assignees. A work item must match all of them.'
          },
          label_name: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Label names. A work item must have all of them.'
          },
          milestone_title: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Milestone titles. Cannot be combined with milestone_wildcard_id.'
          },
          milestone_wildcard_id: {
            type: 'string',
            enum: %w[NONE ANY STARTED UPCOMING],
            description: 'Milestone wildcard. Cannot be combined with milestone_title.'
          },
          types: {
            type: 'array',
            items: {
              type: 'string',
              enum: %w[ISSUE INCIDENT TEST_CASE REQUIREMENT TASK TICKET OBJECTIVE KEY_RESULT EPIC]
            },
            description: 'Work item types to include, for example ["ISSUE", "TASK"].'
          },
          parent_iid: {
            type: 'integer',
            description: 'IID of a parent work item in the given project or group, for example 45 for &45. ' \
              'Returns its direct children.'
          },
          created_after: {
            type: 'string',
            description: 'Created after this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          created_before: {
            type: 'string',
            description: 'Created before this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          updated_after: {
            type: 'string',
            description: 'Updated after this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          updated_before: {
            type: 'string',
            description: 'Updated before this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          due_after: {
            type: 'string',
            description: 'Due after this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          due_before: {
            type: 'string',
            description: 'Due before this time (ISO 8601; date-only means start of day, offsets honored).'
          },
          sort: {
            type: 'string',
            enum: %w[
              CLOSED_AT_ASC
              CLOSED_AT_DESC
              ESCALATION_STATUS_ASC
              ESCALATION_STATUS_DESC
              POPULARITY_ASC
              POPULARITY_DESC
              PRIORITY_ASC
              PRIORITY_DESC
              RELATIVE_POSITION_ASC
              SEVERITY_ASC
              SEVERITY_DESC
              UPDATED_DESC
              UPDATED_ASC
              CREATED_DESC
              CREATED_ASC
              TITLE_ASC
              TITLE_DESC
            ],
            description: 'Sort order.'
          },
          first: {
            type: 'integer',
            description: 'Number of work items to return after the cursor (forward pagination). Max 100.',
            minimum: 1,
            maximum: 100
          },
          after: {
            type: 'string',
            description: 'Cursor for forward pagination of work items. Use pageInfo.endCursor from a previous ' \
              'response.'
          },
          health_status_filter: {
            type: 'string',
            enum: %w[onTrack needsAttention atRisk],
            description: 'Filter by health status.'
          },
          status: {
            type: 'object',
            properties: {
              name: {
                type: 'string',
                description: 'Status name, for example "In progress".'
              }
            },
            required: %w[name],
            additionalProperties: false,
            description: 'Filter by custom status.'
          }
        },
        additionalProperties: false
      })
    end
  end

  describe '#execute with EE filters' do
    before do
      stub_licensed_features(issuable_health_status: true)
    end

    let_it_be(:on_track_work_item) do
      create(:work_item, project: project, title: 'On track issue', health_status: :on_track)
    end

    let_it_be(:at_risk_work_item) do
      create(:work_item, project: project, title: 'At risk issue', health_status: :at_risk)
    end

    let(:params) { { arguments: { project_id: project.id.to_s, health_status_filter: 'onTrack' } } }

    it 'filters by health status while keeping rows compact', :aggregate_failures do
      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)

      rows = result[:structuredContent]['work_items']
      expect(rows.pluck('title')).to contain_exactly('On track issue')
      expect(rows.first.keys).to match_array(%w[id iid title state webUrl reference createdAt updatedAt workItemType])
    end

    context 'with the status filter' do
      before do
        stub_licensed_features(issuable_health_status: true, work_item_status: true)
      end

      let_it_be(:in_progress_work_item) do
        create(:work_item, project: project, title: 'In progress issue').tap do |work_item|
          create(:work_item_current_status, work_item: work_item, system_defined_status_id: 2)
        end
      end

      let(:params) { { arguments: { project_id: project.id.to_s, status: { name: 'In progress' } } } }

      it 'filters by status name' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['work_items'].pluck('title')).to contain_exactly('In progress issue')
      end
    end
  end
end
