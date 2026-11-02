# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Explore::GroupsController, feature_category: :groups_and_projects do
  let_it_be(:user) { create(:user) }

  describe 'GET #index' do
    subject { get explore_groups_path }

    before do
      sign_in(user)
    end

    it_behaves_like 'pushes saas feature in request', :group_project_permanent_deletion_confirmation
    it_behaves_like 'pushes dedicated feature in request', :group_project_permanent_deletion_confirmation
  end
end
