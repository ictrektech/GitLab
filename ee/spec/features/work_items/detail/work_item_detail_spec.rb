# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Work item detail', :js, feature_category: :team_planning do
  let_it_be_with_refind(:user) { create(:user) }

  let_it_be(:group) { create(:group, :nested) }
  let_it_be(:project) { create(:project, :public, namespace: group, developers: user) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let(:work_items_path) { project_work_item_path(project, work_item.iid) }

  context 'for signed in user' do
    before do
      stub_licensed_features(work_item_status: true)
      sign_in(user)
      visit work_items_path
    end

    # Weight is covered by ee/spec/frontend/integration/work_items/details/weight_spec.js
    # Status is covered by ee/spec/frontend/integration/work_items/details/status_spec.js
    # A user who cannot edit the work item's metadata is covered by
    # ee/spec/frontend/integration/work_items/details/read_only_sidebar_spec.js
    it_behaves_like 'work items iteration'
  end
end
