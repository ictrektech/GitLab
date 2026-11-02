# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Base::ApiTool, feature_category: :ai_agents do
  describe '#governed_containers' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:epic_group) { create(:group) }
    let_it_be(:epic) { create(:epic, group: epic_group) }

    let(:create_issue_tool) { Mcp::Tools::Manager.new.list_tools['create_issue'] }

    subject(:resolved) { create_issue_tool.governed_containers(arguments.with_indifferent_access) }

    context 'when an issue is created under an epic' do
      let(:arguments) { { id: project.id.to_s, title: 'Issue', epic_id: epic.id } }

      it 'governs the call by the project and the epic group', :aggregate_failures do
        expect(resolved.containers).to contain_exactly(project, epic_group)
        expect(resolved.named).to eq(2)
      end
    end

    context 'when the epic does not exist' do
      let(:arguments) { { id: project.id.to_s, title: 'Issue', epic_id: non_existing_record_id } }

      it 'counts the epic so the call is refused rather than ungoverned', :aggregate_failures do
        expect(resolved.containers).to eq([project])
        expect(resolved.named).to eq(2)
      end
    end

    context 'when no epic is named' do
      let(:arguments) { { id: project.id.to_s, title: 'Issue' } }

      it 'governs the call by the project alone', :aggregate_failures do
        expect(resolved.containers).to eq([project])
        expect(resolved.named).to eq(1)
      end
    end
  end
end
