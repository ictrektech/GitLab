# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::PullRequestImporter, :clean_gitlab_redis_shared_state, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be_with_reload(:project) do
    create(:project, :repository, :in_group, :github_import, :import_user_mapping_enabled)
  end

  let_it_be(:user_representation) { Gitlab::GithubImport::Representation::User.new(id: 4, login: 'alice') }
  let_it_be(:source_user) { generate_source_user(project, user_representation.id) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:updated_at) { Time.utc(2024, 11, 6, 20, 10, 15) }
  let(:provider_id) { 4_679_385_367 }
  let(:continuous_sync) { true }

  let(:pull_request) do
    Gitlab::GithubImport::Representation::PullRequest.new(
      iid: 42,
      title: 'My Pull Request',
      description: 'This is my pull request',
      source_branch: 'feature',
      source_branch_sha: project.repository.commit('feature').id,
      target_branch: 'master',
      target_branch_sha: project.repository.commit('master').id,
      source_repository_id: 400,
      target_repository_id: 200,
      source_repository_owner: user_representation.login,
      state: :opened,
      author: user_representation,
      created_at: updated_at,
      updated_at: updated_at,
      provider_id: provider_id
    )
  end

  subject(:importer) { described_class.new(pull_request, project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!
    allow(importer).to receive(:insert_git_data)
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the created merge request' do
      merge_request = importer.execute

      expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
        have_attributes(
          repository: repository,
          kind: 'pull_request',
          provider_object_xid: provider_id,
          provider_updated_at: updated_at,
          merge_request: merge_request
        )
      )
    end

    context 'without an updated_at timestamp' do
      let(:updated_at) { nil }

      it 'maps the created merge request with a nil provider_updated_at' do
        merge_request = importer.execute

        expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
          have_attributes(provider_object_xid: provider_id, provider_updated_at: nil, merge_request: merge_request)
        )
      end
    end

    it 'writes no mapping when applying Git data fails' do
      allow(importer).to receive(:insert_git_data).and_raise(ActiveRecord::StatementInvalid)

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)
        .and not_change { Import::Sync::ExternalObject.count }
    end

    it 'leaves one merge request and one mapping when the job is retried' do
      first = importer.execute
      second = described_class.new(pull_request, project, client).tap do |retry_importer|
        allow(retry_importer).to receive(:insert_git_data)
      end.execute

      expect(second).to eq(first)
      expect(MergeRequest.where(project_id: project.id).count).to eq(1)
      expect(Import::Sync::ExternalObject.where(project_id: project.id).count).to eq(1)
    end

    context 'without a provider id' do
      let(:provider_id) { nil }

      it 'imports the merge request without a mapping' do
        expect { importer.execute }.to change { MergeRequest.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute }.to change { MergeRequest.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the repository is provider_canonical' do
      before do
        repository.update!(authority_state: :provider_canonical)
      end

      it 'writes no mapping' do
        expect { importer.execute }.to change { MergeRequest.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'writes no mapping and does not query the mappings' do
      recorder = ActiveRecord::QueryRecorder.new { importer.execute }

      expect(recorder.log.grep(/import_sync_external_objects/)).to be_empty
    end
  end
end
