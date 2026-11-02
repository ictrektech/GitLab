# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Duo Agent Platform session <-> pipeline links', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:public_project) { create(:project, :public) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # The pipeline the fix_pipeline flow was initiated against, and a second one linked
  # to the same session.
  let_it_be(:source_artifact) { create(:ci_pipeline, project: project) }
  let_it_be(:other_artifact) { create(:ci_pipeline, project: project) }

  def create_artifact(project)
    create(:ci_pipeline, project: project)
  end

  # The `link_type` enum currently has only one value (`source`), so both links share
  # it and the filter cannot exclude anything. When a second type is added, drop the
  # `other_link_type` override to assert exclusion.
  it_behaves_like 'a GraphQL API for Duo Agent Platform session links',
    artifact: :pipeline, other_link_type: :source do
    # Pipelines are reached through their project rather than a top-level query field,
    # so the token also has to cross the project and pipeline boundaries.
    let(:artifact_data_path) { [:project, :pipeline] }
    let(:artifact_read_permissions) { [:read_project, :read_pipeline] }

    before do
      stub_licensed_features(ai_workflows: true)
    end

    def artifact_query(record, selection)
      %(project(fullPath: "#{record.project.full_path}") { pipeline(iid: "#{record.iid}") { #{selection} } })
    end
  end
end
