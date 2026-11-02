# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User manage saved views list', :js, feature_category: :planning_views do
  include WorkItemsHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:issue) { create(:work_item, :issue, project: project, title: 'Test issue') }

  before_all do
    group.add_planner(user)
  end

  context 'when user has planner role' do
    before do
      stub_licensed_features(epics: true)
      sign_in(user)
    end

    context 'when creating a view from the add view dropdown' do
      before do
        visit group_work_items_path(group)
        wait_for_all_requests
      end

      include_examples 'saved view creation from add view dropdown'
    end
  end
end
