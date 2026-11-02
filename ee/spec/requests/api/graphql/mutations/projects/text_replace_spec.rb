# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "projectTextReplace", feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, owner_of: project) }
  let_it_be(:import_sync_repository) do
    project.update!(import_type: 'github')

    create(:import_sync_repository, project: project,
      authority_state: :provider_canonical)
  end

  let(:replacements) { %w[p455w0rd] }
  let(:mutation) do
    graphql_mutation(:project_text_replace, { project_path: project.full_path, replacements: replacements })
  end

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    project.association(:import_sync_repository).reset
  end

  context 'when continuous GitHub sync is on' do
    it 'rejects the mutation without scheduling a history rewrite' do
      expect(::Repositories::RewriteHistoryWorker).not_to receive(:perform_async)

      post_mutation

      expect(graphql_errors).to include(a_hash_including(
        'message' => Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
      ))
    end
  end
end
