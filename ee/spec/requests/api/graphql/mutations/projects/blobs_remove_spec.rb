# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "projectBlobsRemove", feature_category: :source_code_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:current_user) { create(:user, owner_of: project) }
  let_it_be(:import_sync_repository) do
    project.update!(import_type: 'github')

    create(:import_sync_repository, project: project,
      authority_state: :provider_canonical)
  end

  let(:blob_oids) { ['53855584db773c3df5b5f61f72974cb298822fbb'] }
  let(:mutation) do
    graphql_mutation(:project_blobs_remove, { project_path: project.full_path, blob_oids: blob_oids })
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
