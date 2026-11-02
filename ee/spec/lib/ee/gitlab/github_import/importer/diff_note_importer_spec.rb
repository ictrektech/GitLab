# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::DiffNoteImporter, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be_with_reload(:project) do
    create(:project, :repository, :in_group, :github_import, :import_user_mapping_enabled)
  end

  let_it_be(:source_user) { generate_source_user(project, 1000) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:continuous_sync) { true }
  let(:note_id) { 2_001 }
  let(:updated_at) { Time.utc(2022, 7, 27, 14, 41, 11) }

  let(:note_representation) do
    Gitlab::GithubImport::Representation::DiffNote.new(
      noteable_type: 'MergeRequest',
      noteable_id: merge_request.iid,
      commit_id: '123abc',
      original_commit_id: 'original123abc',
      file_path: 'files/ruby/popen.rb',
      author: Gitlab::GithubImport::Representation::User.new(
        id: source_user.source_user_identifier, login: source_user.source_username
      ),
      note: 'Hello',
      created_at: updated_at,
      updated_at: updated_at,
      end_line: 15,
      note_id: note_id,
      diff_hunk: "@@ -14 +14 @@\n-Hello\n+Hello world",
      side: 'RIGHT',
      discussion_id: 'b' * 40
    )
  end

  subject(:importer) { described_class.new(note_representation, project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!

    allow_next_instance_of(Gitlab::GithubImport::IssuableFinder) do |finder|
      allow(finder).to receive(:database_id).and_return(merge_request.id)
    end
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the created diff note' do
      expect { importer.execute }.to change { LegacyDiffNote.count }.by(1)

      expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
        have_attributes(
          repository: repository,
          kind: 'review_comment',
          provider_object_xid: note_id,
          provider_updated_at: updated_at,
          note: merge_request.notes.last
        )
      )
    end

    it 'inserts no second diff note when the job is retried' do
      importer.execute

      expect { described_class.new(note_representation, project, client).execute }
        .to not_change { Note.count }.and not_change { Import::Sync::ExternalObject.count }
    end

    context 'when the comment has a suggestion' do
      let(:note_representation) do
        Gitlab::GithubImport::Representation::DiffNote.from_json_hash(
          super().to_hash.merge(note: "```suggestion\nHello world\n```")
        )
      end

      it 'imports it as a DiffNote and maps it' do
        expect { importer.execute }.to change { DiffNote.count }.by(1)

        expect(Import::Sync::ExternalObject.find_by(kind: :review_comment, provider_object_xid: note_id))
          .to have_attributes(note: DiffNote.last, provider_updated_at: updated_at)
      end

      it 'claims the note when a post-save step fails, so the retry inserts no second note',
        :clean_gitlab_redis_shared_state do
        failed = false
        allow_next_instance_of(Suggestions::CreateService) do |service|
          allow(service).to receive(:execute).and_wrap_original do |original|
            next original.call if failed

            failed = true
            raise ActiveRecord::StatementInvalid
          end
        end

        expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)

        expect { described_class.new(note_representation, project, client).execute }
          .not_to change { DiffNote.count }
        expect(DiffNote.count).to eq(1)
        expect(Import::Sync::ExternalObject.where(kind: :review_comment, provider_object_xid: note_id))
          .to contain_exactly(have_attributes(note: DiffNote.last, provider_updated_at: nil))
        expect(placeholder_user_references(Import::SOURCE_GITHUB, project.import_state.id))
          .to contain_exactly(['DiffNote', DiffNote.last.id, 'author_id', source_user.id])
      end
    end

    it 'claims the note when the mapping fails once, so the retry inserts no second note' do
      failed = false
      allow(Import::Sync::ExternalObject).to receive(:record!).and_wrap_original do |original, **kwargs|
        next original.call(**kwargs) if failed

        failed = true
        raise ActiveRecord::StatementInvalid
      end

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)

      expect { described_class.new(note_representation, project, client).execute }
        .not_to change { Note.count }
      expect(Note.count).to eq(1)
      expect(Import::Sync::ExternalObject.where(kind: :review_comment, provider_object_xid: note_id))
        .to contain_exactly(have_attributes(note: Note.last, provider_updated_at: nil))
    end

    it 'raises the original error and tracks the failed claim when the mapping cannot be written' do
      allow(Import::Sync::ExternalObject).to receive(:record!).and_raise(ActiveRecord::StatementInvalid, 'mapping')
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(ActiveRecord::StatementInvalid), hash_including(provider_object_xid: note_id))

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid, 'mapping')
    end

    it 'raises the original error and records nothing when no note was saved' do
      allow(ApplicationRecord).to receive(:legacy_bulk_insert).and_raise(ActiveRecord::StatementInvalid, 'insert')
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid, 'insert')
      expect(Import::Sync::ExternalObject.count).to eq(0)
    end

    context 'when the note has no author' do
      let(:note_representation) do
        Gitlab::GithubImport::Representation::DiffNote.from_json_hash(super().to_hash.merge(author: nil))
      end

      it 'claims the note when the mapping fails once' do
        failed = false
        allow(Import::Sync::ExternalObject).to receive(:record!).and_wrap_original do |original, **kwargs|
          next original.call(**kwargs) if failed

          failed = true
          raise ActiveRecord::StatementInvalid
        end
        expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

        expect { importer.execute }.to raise_error(ActiveRecord::StatementInvalid)
        expect(Import::Sync::ExternalObject.where(kind: :review_comment, provider_object_xid: note_id))
          .to contain_exactly(have_attributes(note: Note.last, provider_updated_at: nil))
      end
    end

    it 'looks up the author once and tracks nothing when the lookup fails' do
      expect_next_instance_of(Gitlab::GithubImport::UserFinder) do |finder|
        expect(finder).to receive(:author_id_for).once.and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end
      expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { importer.execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
    end

    context 'when GitHub sent no update time' do
      let(:note_representation) do
        Gitlab::GithubImport::Representation::DiffNote.from_json_hash(super().to_hash.merge(updated_at: nil))
      end

      it 'maps the diff note without a version' do
        importer.execute

        expect(Import::Sync::ExternalObject.find_by(kind: :review_comment, provider_object_xid: note_id))
          .to have_attributes(note: merge_request.notes.last, provider_updated_at: nil)
      end
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute }.to change { Note.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the repository is provider_canonical' do
      before do
        repository.update!(authority_state: :provider_canonical)
      end

      it 'writes no mapping' do
        expect { importer.execute }.to change { Note.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'writes no mapping and does not query the mappings' do
      recorder = ActiveRecord::QueryRecorder.new { importer.execute }

      expect(recorder.log.grep(/import_sync_external_objects/)).to be_empty
      expect(Note.count).to eq(1)
    end
  end
end
