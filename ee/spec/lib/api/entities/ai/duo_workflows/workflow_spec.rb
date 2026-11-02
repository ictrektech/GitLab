# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::Ai::DuoWorkflows::Workflow, feature_category: :duo_agent_platform do
  subject(:serialized) { described_class.new(workflow).as_json }

  context 'when the session belongs to a project' do
    let(:project) { build_stubbed(:project) }
    let(:workflow) { build_stubbed(:duo_workflows_workflow, id: 42, project: project, namespace: nil) }

    it 'exposes the canonical session URL' do
      expect(serialized[:web_url]).to eq(workflow.web_url)
    end
  end

  context 'when the session belongs to a namespace' do
    let(:namespace) { build_stubbed(:group) }
    let(:workflow) { build_stubbed(:duo_workflows_workflow, project: nil, namespace: namespace) }

    it 'exposes the group session URL' do
      expected_url =
        "#{Gitlab.config.gitlab.url}/groups/#{namespace.full_path}/-/automate/agent-sessions/#{workflow.id}"

      expect(serialized[:web_url]).to eq(expected_url)
    end
  end
end
