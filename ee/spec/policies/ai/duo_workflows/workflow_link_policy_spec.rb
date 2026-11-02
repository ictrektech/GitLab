# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkflowLinkPolicy, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let(:user) { build_stubbed(:user) }

  where(:factory) do
    %i[
      duo_workflows_workflow_merge_request
      duo_workflows_workflow_note
      duo_workflows_workflow_pipeline
      duo_workflows_workflow_work_item
      duo_workflows_workflow_workflow
    ]
  end

  with_them do
    subject(:policy) { described_class.new(user, link) }

    let(:link) { build_stubbed(factory) }

    it { is_expected.to delegate_to(Ai::DuoWorkflows::WorkflowPolicy) }

    it 'is the policy resolved for the join model' do
      expect(DeclarativePolicy.policy_for(user, link)).to be_a(described_class)
    end

    it 'delegates to the session that owns the link, not the linked artifact' do
      expect(policy.delegated_policies.values.map(&:subject)).to contain_exactly(link.workflow)
    end
  end
end
