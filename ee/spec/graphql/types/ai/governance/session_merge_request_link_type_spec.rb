# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Governance::SessionMergeRequestLinkType, feature_category: :compliance_management do
  include_context 'with AI governance session links for a compliance user'

  let_it_be(:readable_link) { create(:duo_workflows_workflow_merge_request, workflow: workflow) }
  let_it_be(:unreadable_link) do
    create(:duo_workflows_workflow_merge_request, workflow: workflow,
      merge_request: create(:merge_request, source_project: private_project))
  end

  let(:artifact_field) { 'mergeRequest' }
  let(:link_type_enum) { 'DuoWorkflowMergeRequestLinkType' }
  let(:readable_artifact_gid) { readable_link.merge_request.to_global_id.to_s }

  specify { expect(described_class.graphql_name).to eq('AiGovernanceSessionMergeRequestLink') }

  it_behaves_like 'an AI governance session link type'
end
