# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::WorkItems::LinkWorkItemsService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }
  let_it_be(:source_work_item) { create(:work_item, :issue, project: project, iid: 1) }
  let_it_be(:target_work_item) { create(:work_item, :issue, project: project, iid: 2) }

  let(:service) { described_class.new(name: 'link_work_items') }
  let(:request) { instance_double(ActionDispatch::Request) }
  let(:target_gid) { target_work_item.to_global_id.to_s }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe '#description' do
    it 'includes blocks and blocked_by in description' do
      expect(service.description).to include('relates_to, blocks, blocked_by')
    end
  end

  describe '#input_schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(service.input_schema).to eq({
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'GitLab URL for the source work item.'
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
            description: 'Internal ID of the source work item. Required if URL is not provided.'
          },
          work_items_ids: {
            type: 'array',
            description: 'Work items to link to: plain iids (resolved in the same project or group as the ' \
              'source) or global IDs (gid://gitlab/WorkItem/<id>) for work items in other projects or ' \
              'groups. Maximum 10 items.',
            items: {
              anyOf: [{ type: 'integer' }, { type: 'string' }]
            },
            minItems: 1,
            maxItems: 10
          },
          link_type: {
            type: 'string',
            description: 'Type of relationship between the work items.',
            enum: %w[relates_to blocks blocked_by]
          }
        },
        required: %w[work_items_ids],
        additionalProperties: false
      })
    end
  end

  describe '#execute' do
    subject(:result) { service.execute(request: request, params: params) }

    context 'when link_type is blocks' do
      before do
        stub_licensed_features(blocked_work_items: true)
      end

      let(:params) do
        {
          arguments: {
            project_id: project.id.to_s,
            work_item_iid: source_work_item.iid,
            work_items_ids: [target_gid],
            link_type: 'blocks'
          }
        }
      end

      it 'links work items with blocks relationship' do
        expect(result[:isError]).to be(false)
      end
    end

    context 'when link_type is blocked_by' do
      before do
        stub_licensed_features(blocked_work_items: true)
      end

      let(:params) do
        {
          arguments: {
            project_id: project.id.to_s,
            work_item_iid: source_work_item.iid,
            work_items_ids: [target_gid],
            link_type: 'blocked_by'
          }
        }
      end

      it 'links work items with blocked_by relationship' do
        expect(result[:isError]).to be(false)
      end
    end

    context 'when link_type is blocks but feature is not licensed' do
      before do
        stub_licensed_features(blocked_work_items: false)
      end

      let(:params) do
        {
          arguments: {
            project_id: project.id.to_s,
            work_item_iid: source_work_item.iid,
            work_items_ids: [target_gid],
            link_type: 'blocks'
          }
        }
      end

      it 'returns an error about subscription tier' do
        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text])
          .to include('Blocked work items are not available for the current subscription tier')
      end
    end
  end
end
