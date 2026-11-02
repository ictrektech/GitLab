# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionWorkItemLinkType, feature_category: :compliance_management do
  include_context 'with AI governance session links for a compliance user'

  let_it_be(:readable_link) { create(:duo_workflows_workflow_work_item, workflow: workflow) }
  let_it_be(:unreadable_link) do
    create(:duo_workflows_workflow_work_item, workflow: workflow,
      work_item: create(:work_item, project: private_project))
  end

  let(:artifact_field) { 'workItem' }
  let(:link_type_enum) { 'DuoWorkflowWorkItemLinkType' }
  let(:readable_artifact_gid) { readable_link.work_item.to_global_id.to_s }

  specify { expect(described_class.graphql_name).to eq('AiGovernanceSessionWorkItemLink') }

  it_behaves_like 'an AI governance session link type'
end
