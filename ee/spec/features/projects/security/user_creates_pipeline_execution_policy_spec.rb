# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "User creates pipeline execution policy", :js, feature_category: :security_policy_management do
  include ListboxHelpers

  let_it_be(:owner) { create(:user, :with_namespace) }
  let_it_be(:group) { create(:group, owners: owner) }
  let_it_be_with_reload(:project) { create(:project, :repository, namespace: group, name: 'Project 1') }
  let_it_be(:path_to_policy_editor) { new_project_security_policy_path(project) }
  let_it_be(:policy_management_project) { create(:project, :repository, namespace: group) }
  let_it_be(:policy_configuration) do
    create(
      :security_orchestration_policy_configuration,
      security_policy_management_project: policy_management_project,
      project: project
    )
  end

  before do
    sign_in(owner)
    stub_licensed_features(security_orchestration_policies: true)
    visit(path_to_policy_editor)
    within_testid("pipeline_execution_policy-card") do
      click_link _('Select policy')
    end
    find_by_testid('policy-name-text')
  end

  # Client-side half: ee/spec/frontend/integration/security_policies/editor/pipeline_execution_create_spec.js.
  # Kept here for the half that cannot move: the backend accepting a cross-project file reference.
  it "creates an merge request for a valid policy" do
    fill_in _('Name'), with: 'Run custom pipeline jobs'
    within_testid('disabled-action') do
      select_from_listbox project.name, from: 'Select projects'
      fill_in 'file-path', with: '.gitlab-ci.yml'
    end
    click_button _('Configure with a merge request')

    expect(page).to have_current_path(project_merge_request_path(policy_management_project, 1))
  end
end
