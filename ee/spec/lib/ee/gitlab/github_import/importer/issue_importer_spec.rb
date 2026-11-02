# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::IssueImporter, :clean_gitlab_redis_shared_state, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be(:work_item_type_id) { build(:work_item_system_defined_type, :issue).id }
  let_it_be_with_reload(:project) { create(:project, :github_import, :import_user_mapping_enabled, :in_group) }
  let_it_be(:source_user) { generate_source_user(project, '4') }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:updated_at) { Time.utc(2017, 1, 1, 12, 15) }
  let(:provider_id) { 987_654 }
  let(:author) { Gitlab::GithubImport::Representation::User.new(id: 4, login: 'alice') }
  let(:continuous_sync) { true }

  let(:issue) do
    Gitlab::GithubImport::Representation::Issue.new(
      iid: 42, title: 'My Issue', description: 'This is my issue', state: :opened, assignees: [],
      label_names: [], author: author, created_at: updated_at, updated_at: updated_at,
      pull_request: false, work_item_type_id: work_item_type_id, provider_id: provider_id
    )
  end

  subject(:importer) { described_class.new(issue, project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the created issue' do
      new_issue = nil

      expect { new_issue = importer.execute }.to change { Import::Sync::ExternalObject.count }.by(1)

      expect(Import::Sync::ExternalObject.last).to have_attributes(
        repository: repository,
        kind: 'issue',
        provider_object_xid: provider_id,
        provider_updated_at: updated_at,
        issue: new_issue
      )
    end

    context 'without an updated_at timestamp' do
      let(:updated_at) { nil }

      it 'maps the created issue with a nil provider_updated_at' do
        new_issue = importer.execute

        expect(Import::Sync::ExternalObject.last).to have_attributes(
          provider_object_xid: provider_id,
          provider_updated_at: nil,
          issue: new_issue
        )
      end
    end

    it 'rolls the issue back when the mapping cannot be written' do
      allow(Import::Sync::ExternalObject).to receive(:record!).and_raise(ActiveRecord::StatementInvalid)

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)
        .and not_change { Issue.count }
    end

    context 'without a provider id' do
      let(:provider_id) { nil }

      it 'imports the issue without a mapping' do
        expect { importer.execute }.to change { Issue.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute }.to change { Issue.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the repository is provider_canonical' do
      before do
        repository.update!(authority_state: :provider_canonical)
      end

      it 'writes no mapping' do
        expect { importer.execute }.to change { Issue.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'writes no mapping and does not query the mappings' do
      recorder = ActiveRecord::QueryRecorder.new { importer.execute }

      expect(recorder.log.grep(/import_sync_external_objects/)).to be_empty
      expect(Import::Sync::ExternalObject.count).to eq(0)
    end
  end
end
