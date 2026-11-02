# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session <-> merge request links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:public_project) { create(:project, :public, :repository) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # The merge request we start the traversal from, and a second one the session created.
  let_it_be(:source_artifact) { create(:merge_request, source_project: project) }
  let_it_be(:other_artifact) { create_artifact(project) }

  def create_artifact(project)
    create(:merge_request, source_project: project, source_branch: generate(:branch), target_branch: 'master')
  end

  it_behaves_like 'a GraphQL API for Duo Agent Platform session links', artifact: :merge_request
end
