# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Boards::MilestonesFinder, feature_category: :planning_views do
  describe '#execute' do
    let_it_be(:group) { create(:group) }
    let_it_be(:nested_group) { create(:group, parent: group) }
    let_it_be(:deep_nested_group) { create(:group, parent: group) }

    let_it_be(:group_project) { create(:project, group: group) }
    let_it_be(:nested_group_project) { create(:project, group: nested_group) }

    let_it_be(:group_milestone) { create(:milestone, group: group, project: nil) }
    let_it_be(:group_project_milestone) { create(:milestone, project: group_project, group: nil) }
    let_it_be(:nested_group_project_milestone) { create(:milestone, project: nested_group_project, group: nil) }
    let_it_be(:nested_group_milestone) { create(:milestone, group: nested_group, project: nil) }
    let_it_be(:deep_nested_group_milestone) { create(:milestone, group: deep_nested_group, project: nil) }

    let_it_be(:user) { create(:user) }

    let(:finder) { described_class.new(board, user) }

    before_all do
      group.add_developer(user)
    end

    context 'when project board' do
      let_it_be(:board) { create(:board, project: nested_group_project, group: nil) }

      it 'returns milestones from board project and ancestors groups' do
        results = finder.execute

        expect(results).to contain_exactly(
          nested_group_project_milestone,
          nested_group_milestone,
          group_milestone
        )
      end
    end

    context 'when group board' do
      let_it_be(:board) { create(:board, project: nil, group: nested_group) }

      it 'returns milestones from board group and its ancestors' do
        results = finder.execute

        expect(results).to contain_exactly(group_milestone, nested_group_milestone)
      end
    end
  end
end
