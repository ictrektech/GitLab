# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::SaveWorkItemService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let(:service) { described_class.new(name: 'save_work_item') }
  let(:request) { instance_double(ActionDispatch::Request) }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe '#input_schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(service.input_schema).to eq({
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'GitLab URL for the project, group, or work item. Provide exactly one of url, ' \
              'project_id, or group_id.'
          },
          group_id: {
            type: 'string',
            description: 'ID or path of the group. Required if URL and project_id are not provided.'
          },
          project_id: {
            type: 'string',
            description: 'ID or path of the project. Required if URL and group_id are not provided.'
          },
          work_item_iid: {
            type: 'integer',
            description: 'Positive internal ID of the work item to update. Omit to create a new work item.'
          },
          title: {
            type: 'string',
            description: 'Title. Required on create.'
          },
          type_name: {
            type: 'string',
            description: 'Work item type name, for example "Issue", "Task", "Epic". Required on create. Valid ' \
              'types depend on the namespace and license; invalid values return the list of valid ' \
              'ones.'
          },
          description: {
            type: 'string',
            description: 'Description in GitLab Flavored Markdown (max 1048576 characters). Lines beginning with ' \
              '"/" are rejected to avoid triggering quick actions. Use add_labels, assignee_ids, and ' \
              'the other fields instead.',
            maxLength: 1048576
          },
          assignee_ids: {
            type: 'array',
            items: {
              type: 'integer'
            },
            maxItems: 100,
            description: 'User IDs to assign to the work item.'
          },
          label_ids: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Label IDs or global IDs. Create only; on update use add_label_ids/remove_label_ids.'
          },
          labels: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Names of the labels to set, resolved in the project or group and its ancestor groups. ' \
              'Create only; on update use add_labels/remove_labels.'
          },
          add_label_ids: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Update only. Label IDs or global IDs to add.'
          },
          add_labels: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Update only. Names of the labels to add.'
          },
          remove_label_ids: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Update only. Label IDs or global IDs to remove.'
          },
          remove_labels: {
            type: 'array',
            items: {
              type: 'string'
            },
            maxItems: 100,
            description: 'Update only. Names of the labels to remove.'
          },
          milestone_id: {
            type: 'string',
            description: 'ID or global ID of the milestone to assign, validated against the project or group and ' \
              'its ancestor groups. Wins over milestone when both are given.'
          },
          milestone: {
            type: 'string',
            description: 'Title of the milestone to assign, resolved among the milestones of the project or ' \
              'group and its ancestor groups.'
          },
          confidential: {
            type: 'boolean',
            description: 'Sets the work item confidentiality.'
          },
          start_date: {
            type: 'string',
            description: 'Start date, YYYY-MM-DD.'
          },
          due_date: {
            type: 'string',
            description: 'Due date, YYYY-MM-DD.'
          },
          state: {
            type: 'string',
            enum: %w[opened closed],
            description: 'Update only. closed closes the work item, opened reopens it.'
          },
          parent_id: {
            type: 'string',
            description: 'Global ID or numeric ID of the parent work item (hierarchy).'
          },
          todo_action: {
            type: 'string',
            enum: %w[add mark_as_done],
            description: 'Update only. add adds a to-do for the current user, mark_as_done marks to-dos as done.'
          },
          todo_id: {
            type: 'string',
            description: 'Update only. Global ID or numeric ID of the to-do; omit to update all to-dos on the ' \
              'work item.'
          },
          health_status: {
            type: 'string',
            enum: %w[onTrack needsAttention atRisk],
            description: 'Health status of the work item.'
          },
          weight: {
            type: 'integer',
            minimum: 0,
            description: 'Weight of the work item.'
          },
          clear_weight: {
            type: 'boolean',
            description: 'Update only. Removes the weight; wins over weight.'
          },
          status_id: {
            type: 'string',
            description: 'Global ID of the status to set.'
          },
          is_fixed: {
            type: 'boolean',
            description: 'Whether start and due dates are fixed. When false, dates roll up from child items and ' \
              'start_date/due_date are ignored.'
          },
          agent_plan: {
            type: 'string',
            description: 'Markdown content of the agent plan. Requires the workplan feature.'
          },
          readiness_score: {
            type: 'integer',
            minimum: 0,
            maximum: 100,
            description: 'Readiness score of the agent plan (0-100). Requires the workplan_score feature flag. ' \
              'Omit to leave the existing score unchanged.'
          }
        },
        required: [],
        additionalProperties: false
      })
    end
  end

  describe '#execute' do
    before do
      stub_licensed_features(issue_weights: true, ai_workflows: true)
    end

    it 'creates a work item with a weight' do
      result = service.execute(
        request: request,
        params: { arguments: { project_id: project.id.to_s, title: 'Weighted', type_name: 'Issue', weight: 3 } }
      )

      expect(result[:isError]).to be(false)

      created = WorkItem.find(GlobalID.parse(result[:structuredContent]['id']).model_id.to_i)
      expect(created.weight).to eq(3)
    end

    context 'with clear_weight' do
      let_it_be_with_reload(:work_item) { create(:work_item, :issue, project: project, weight: 5) }

      it 'clears the weight' do
        result = service.execute(
          request: request,
          params: { arguments: { project_id: project.id.to_s, work_item_iid: work_item.iid, clear_weight: true } }
        )

        expect(result[:isError]).to be(false)
        expect(work_item.reload.weight).to be_nil
      end
    end

    context 'with readiness_score' do
      let_it_be_with_reload(:work_item) { create(:work_item, :issue, project: project) }

      context 'when workplan_score feature flag is enabled' do
        it 'sets the readiness_score on update' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                work_item_iid: work_item.iid,
                readiness_score: 80
              }
            }
          )

          expect(result[:isError]).to be(false)
          expect(work_item.reload.agent_plan.readiness_score).to eq(80)
        end

        it 'sets the readiness_score on create' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                title: 'Scored item',
                type_name: 'Issue',
                readiness_score: 50
              }
            }
          )

          expect(result[:isError]).to be(false)

          created = WorkItem.find(GlobalID.parse(result[:structuredContent]['id']).model_id.to_i)
          expect(created.agent_plan.readiness_score).to eq(50)
        end
      end

      context 'when workplan_score feature flag is disabled' do
        before do
          stub_feature_flags(workplan_score: false)
        end

        it 'returns an error and does not persist the readiness_score', :aggregate_failures do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.id.to_s,
                work_item_iid: work_item.iid,
                readiness_score: 80
              }
            }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('workplan_score')
          expect(work_item.reload.agent_plan).to be_nil
        end
      end
    end
  end

  describe '#execute with label names on a group-level work item' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:group_label) { create(:group_label, group: group, title: 'strategic') }
    let_it_be_with_reload(:epic_item) { create(:work_item, :epic, namespace: group) }

    before_all do
      group.add_developer(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    it 'resolves the names against the group', :aggregate_failures do
      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, add_labels: %w[strategic] } }
      )

      expect(result[:isError]).to be(false)
      expect(epic_item.reload.labels.map(&:title)).to eq(%w[strategic])
    end

    it 'sets a group milestone by title on the epic', :aggregate_failures do
      group_milestone = create(:milestone, group: group, title: 'Q4')

      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, milestone: 'Q4' } }
      )

      expect(result[:isError]).to be(false)
      expect(epic_item.reload.milestone).to eq(group_milestone)
    end

    it 'rejects an unknown name and names the group', :aggregate_failures do
      result = service.execute(
        request: request,
        params: { arguments: { group_id: group.id.to_s, work_item_iid: epic_item.iid, add_labels: %w[nope] } }
      )

      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include("Labels not found in #{group.full_path}")
    end
  end
end
