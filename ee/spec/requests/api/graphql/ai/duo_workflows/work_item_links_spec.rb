# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session <-> work item links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:public_project) { create(:project, :public) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # The work item we start the traversal from, and a second one the session created.
  let_it_be(:source_artifact) { create(:work_item, project: project) }
  let_it_be(:other_artifact) { create(:work_item, project: project) }

  def create_artifact(project)
    create(:work_item, project: project)
  end

  it_behaves_like 'a GraphQL API for Duo Agent Platform session links', artifact: :work_item
end
