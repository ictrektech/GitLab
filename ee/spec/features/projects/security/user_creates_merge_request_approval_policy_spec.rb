# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "User creates merge request approval policy", :js, feature_category: :security_policy_management do
  let_it_be(:owner) { create(:user, :with_namespace) }
  let_it_be_with_reload(:project) { create(:project, :repository, namespace: owner.namespace) }
  let_it_be_with_reload(:protected_branch) { create(:protected_branch, name: 'spooky-stuff', project: project) }
  let_it_be(:policy_management_project) { create(:project, :repository, namespace: owner.namespace) }
  let_it_be(:path_to_policy_editor) { new_project_security_policy_path(project) }
  let_it_be(:policy_configuration) do
    create(
      :security_orchestration_policy_configuration,
      security_policy_management_project: policy_management_project,
      project: project
    )
  end

  before do
    sign_in(owner)
  end

  it_behaves_like 'creating merge request approval policy with valid properties'
end
