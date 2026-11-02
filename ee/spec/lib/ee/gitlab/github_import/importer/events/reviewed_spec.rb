# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Importer::Events::Reviewed, feature_category: :importers do
  include Import::UserMappingHelper

  let_it_be_with_reload(:project) { create(:project, :in_group, :github_import, :import_user_mapping_enabled) }
  let_it_be(:source_user) { generate_source_user(project, 1000) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, web_endpoint: 'https://github.com') }
  let(:continuous_sync) { true }
  let(:review_id) { 3_001 }
  let(:submitted_at) { '2022-07-27T14:41:11Z' }
  let(:body) { 'Looks good' }

  let(:issue_event) do
    Gitlab::GithubImport::Representation::IssueEvent.new(
      id: review_id,
      actor: { id: source_user.source_user_identifier, login: source_user.source_username },
      event: 'reviewed',
      state: 'approved',
      body: body,
      created_at: submitted_at,
      submitted_at: submitted_at,
      issue: { number: merge_request.iid, pull_request: true }
    )
  end

  subject(:importer) { described_class.new(project, client) }

  before do
    project.build_or_assign_import_data(data: { 'optional_stages' => { 'continuous_sync' => continuous_sync } }).save!
  end

  context 'with a provisioning sync repository' do
    let_it_be_with_reload(:repository) { create(:import_sync_repository, :oauth, project: project) }

    it 'maps the review note' do
      expect { importer.execute(issue_event) }.to change { Note.count }.by(2)

      expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
        have_attributes(
          repository: repository,
          kind: 'review',
          provider_object_xid: review_id,
          provider_updated_at: Time.zone.parse(submitted_at),
          note: merge_request.notes.find_by(system: false)
        )
      )
    end

    context 'when the review has no body' do
      let(:body) { '' }

      it 'maps the approval note' do
        expect { importer.execute(issue_event) }.to change { Note.count }.by(1)

        expect(Import::Sync::ExternalObject.where(project_id: project.id).to_a).to contain_exactly(
          have_attributes(
            kind: 'review', provider_object_xid: review_id, note: merge_request.notes.find_by(system: true)
          )
        )
      end
    end

    context 'when the review has no submission time' do
      let(:submitted_at) { nil }

      it 'maps the review note without a version' do
        importer.execute(issue_event)

        expect(Import::Sync::ExternalObject.find_by(kind: :review, provider_object_xid: review_id))
          .to have_attributes(note: merge_request.notes.find_by(system: false), provider_updated_at: nil)
      end
    end

    context 'when the review adds no note' do
      let(:issue_event) do
        Gitlab::GithubImport::Representation::IssueEvent.new(
          id: review_id,
          actor: { id: source_user.source_user_identifier, login: source_user.source_username },
          event: 'reviewed',
          state: 'commented',
          body: '',
          created_at: submitted_at,
          submitted_at: submitted_at,
          issue: { number: merge_request.iid, pull_request: true }
        )
      end

      it 'writes no mapping' do
        expect { importer.execute(issue_event) }
          .to not_change { Note.count }.and not_change { Import::Sync::ExternalObject.count }
      end
    end

    context 'when the approval fails before any note is saved' do
      let(:body) { '' }

      before do
        allow(Approval).to receive(:create).and_raise(StandardError, 'approval failed')
      end

      it 'writes no mapping' do
        expect { importer.execute(issue_event) }.to raise_error(StandardError, 'approval failed')
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end

    it 'adds no second review note when the job is retried' do
      importer.execute(issue_event)

      expect { described_class.new(project, client).execute(issue_event) }
        .to not_change { Note.count }.and not_change { Import::Sync::ExternalObject.count }
    end

    context 'when the approval fails after the review note is saved' do
      before do
        allow(Approval).to receive(:create).and_raise(StandardError, 'approval failed')
      end

      it 'claims the review note, so the retry adds only the approval' do
        expect { importer.execute(issue_event) }.to raise_error(StandardError, 'approval failed')

        review_note = merge_request.notes.find_by(system: false)
        expect(Import::Sync::ExternalObject.find_by(kind: :review, provider_object_xid: review_id))
          .to have_attributes(note: review_note, provider_updated_at: nil)

        allow(Approval).to receive(:create).and_call_original

        expect { described_class.new(project, client).execute(issue_event) }
          .to change { Approval.count }.by(1)
          .and change { merge_request.notes.where(system: true).count }.by(1)
          .and not_change { merge_request.notes.where(system: false).count }

        expect(Import::Sync::ExternalObject.find_by(kind: :review, provider_object_xid: review_id))
          .to have_attributes(note: review_note, provider_updated_at: Time.zone.parse(submitted_at))
      end
    end

    context 'when continuous sync is disabled for the import' do
      let(:continuous_sync) { false }

      it 'writes no mapping' do
        expect { importer.execute(issue_event) }.to change { Note.count }.by(2)
          .and not_change { Import::Sync::ExternalObject.count }
      end
    end
  end

  context 'without a sync repository' do
    it 'writes no mapping and does not query the mappings' do
      recorder = ActiveRecord::QueryRecorder.new { importer.execute(issue_event) }

      expect(recorder.log.grep(/import_sync_external_objects/)).to be_empty
      expect(Note.count).to eq(2)
    end
  end
end
