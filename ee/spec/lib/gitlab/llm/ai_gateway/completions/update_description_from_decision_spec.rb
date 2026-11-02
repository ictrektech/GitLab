# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision, feature_category: :team_planning do
  let(:options) do
    { title: 'T', description: 'D', question: 'Q?', options: %w[a b], answer: 'a', rationale: 'R', other: 1 }
  end

  let(:prompt_message) { build(:ai_message, ai_action: 'update_description_from_decision') }

  subject(:completion) { described_class.new(prompt_message, nil, options) }

  it 'passes only the decision inputs', :aggregate_failures do
    expect(completion.inputs).to eq(options.except(:other))
  end

  it 'uses the duo_agent_platform unit primitive' do
    expect(completion.send(:unit_primitive_name)).to eq(:duo_agent_platform)
  end

  context 'with a work item as the resource' do
    let_it_be(:work_item) { create(:work_item) }
    let(:prompt_message) { build(:ai_message, ai_action: 'update_description_from_decision', resource: work_item) }

    it 'passes the namespace context', :aggregate_failures do
      expect(completion.namespace_id).to eq(work_item.namespace_id)
      expect(completion.project_id).to eq(work_item.project_id)
      expect(completion.root_namespace).to eq(work_item.root_ancestor)
    end
  end
end
