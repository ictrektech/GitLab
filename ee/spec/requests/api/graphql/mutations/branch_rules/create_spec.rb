# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BranchRuleCreate', feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project, :public) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }
  let_it_be(:import_sync_repository) do
    project.update!(import_type: 'github')

    create(:import_sync_repository, project: project,
      authority_state: :provider_canonical)
  end

  let(:mutation) do
    graphql_mutation(:branch_rule_create, { project_path: project.full_path, name: 'branch_name/*' })
  end

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    project.association(:import_sync_repository).reset
  end

  context 'when continuous GitHub sync is on' do
    it 'rejects the mutation without creating a protected branch' do
      expect { post_mutation }.not_to change { ProtectedBranch.count }
      expect(graphql_errors).to include(a_hash_including(
        'message' => Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
      ))
    end
  end
end
