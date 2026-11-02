# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::Events::Commented, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be_with_reload(:project) { create(:project, :in_group, :github_import, :import_user_mapping_enabled) }
  let_it_be(:source_user) { generate_source_user(project, 1000) }
  let_it_be(:issuable) { create(:issue, project: project) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:continuous_sync) { true }
  let(:comment_id) { 1_196_850_910 }
  let(:updated_at) { '2022-07-27T14:41:11Z' }

  let(:issue_event) do
    Gitlab::GithubImport::Representation::IssueEvent.new(
      id: comment_id,
      actor: { id: source_user.source_user_identifier, login: source_user.source_username },
      event: 'commented',
      created_at: updated_at,
      updated_at: updated_at,
      body: 'This is my note',
      issue: { number: issuable.iid, pull_request: false }
    )
  end

  subject(:importer) { described_class.new(project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!

    allow_next_instance_of(Gitlab::GithubImport::IssuableFinder) do |finder|
      allow(finder).to receive(:database_id).and_return(issuable.id)
    end
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the created note' do
      expect { importer.execute(issue_event) }.to change { Note.count }.by(1)

      expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
        have_attributes(
          repository: repository,
          kind: 'issue_comment',
          provider_object_xid: comment_id,
          provider_updated_at: Time.zone.parse(updated_at),
          note: issuable.notes.last
        )
      )
    end

    context 'without an updated_at timestamp' do
      let(:updated_at) { nil }

      it 'maps the created note with a nil provider_updated_at' do
        expect { importer.execute(issue_event) }.to change { Note.count }.by(1)

        expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
          have_attributes(provider_object_xid: comment_id, provider_updated_at: nil, note: issuable.notes.last)
        )
      end
    end

    it 'returns the mapped note and inserts no second note when the job is retried' do
      importer.execute(issue_event)
      note = Note.last

      expect { described_class.new(project, client).execute(issue_event) }
        .to not_change { Note.count }.and not_change { Import::Sync::ExternalObject.count }

      expect(described_class.new(project, client).execute(issue_event)).to eq(note)
    end

    it 'rolls the note back when the mapping cannot be written' do
      allow(Import::Sync::ExternalObject).to receive(:record!).and_raise(ActiveRecord::StatementInvalid)

      expect { importer.execute(issue_event) }.to raise_error(ActiveRecord::StatementInvalid)
        .and not_change { Note.count }
    end

    it 'records the same mapping idempotently' do
      note = importer.tap { |i| i.execute(issue_event) }.then { Note.last }

      expect do
        2.times do
          Import::Sync::ExternalObject.record!(
            repository: repository, kind: :issue_comment, provider_object_xid: comment_id,
            local_record: note, provider_updated_at: Time.zone.parse(updated_at)
          )
        end
      end.not_to change { Import::Sync::ExternalObject.count }
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute(issue_event) }.to change { Note.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the repository is provider_canonical' do
      before do
        repository.update!(authority_state: :provider_canonical)
      end

      it 'writes no mapping' do
        expect { importer.execute(issue_event) }.to change { Note.count }.by(1)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'writes no mapping and does not query the mappings' do
      recorder = ActiveRecord::QueryRecorder.new { importer.execute(issue_event) }

      expect(recorder.log.grep(/import_sync_external_objects/)).to be_empty
      expect(Note.count).to eq(1)
    end
  end
end
