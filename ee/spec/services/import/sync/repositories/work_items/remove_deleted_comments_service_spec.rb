# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::WorkItems::RemoveDeletedCommentsService, feature_category: :importers do
  let_it_be(:repository) { create(:import_sync_repository, :oauth, provider_full_name: 'example/connected') }
  let_it_be(:project) { repository.project }
  let_it_be(:issue) { create(:issue, project: project, iid: 4, imported_from: :github) }

  let!(:kept_note) { create(:note, project: project, noteable: issue, imported_from: :github) }
  let!(:deleted_note) { create(:note, project: project, noteable: issue, imported_from: :github) }
  let!(:kept_mapping) { map_note(kept_note, 301) }
  let!(:deleted_mapping) { map_note(deleted_note, 302) }

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:lease_context) do
    instance_double(Import::Sync::Repositories::ApplicationLease::Context, renew!: true, verify!: true)
  end

  let(:provider_issue) { { id: 101, number: 4, comments: 1 } }
  let(:unchanged) { true }
  let(:listed_comments) { [{ id: 301 }] }

  let(:service) { described_class.new(repository, client: client, lease_context: lease_context) }

  subject(:execute) { service.execute(issue, provider_issue, unchanged: unchanged) }

  before do
    allow(client).to receive(:each_page)
      .with(:issue_comments, nil, 'example/connected', 4)
      .and_yield(Gitlab::GithubImport::Client::Page.new(listed_comments, nil))
    allow(client).to receive(:issue_comment)
      .with('example/connected', 302)
      .and_raise(Octokit::NotFound)
  end

  def map_note(note, provider_object_xid)
    create(:import_sync_external_object, :issue_comment, repository: repository, note: note,
      provider_object_xid: provider_object_xid)
  end

  it 'removes the note of a comment deleted on GitHub and keeps the others', :aggregate_failures do
    expect(Gitlab::GithubImport::Logger).to receive(:info).with(
      hash_including(message: 'removed GitHub comment deleted on GitHub', note_id: deleted_note.id,
        provider_object_xid: 302)
    )

    execute

    expect(Note.exists?(deleted_note.id)).to be(false)
    expect(Import::Sync::ExternalObject.exists?(deleted_mapping.id)).to be(false)
    expect(kept_note.reload).to be_present
    expect(kept_mapping.reload).to be_present
    expect(client).not_to have_received(:issue_comment).with('example/connected', 301)
    expect(lease_context).to have_received(:verify!)
  end

  context 'when GitHub has as many comments as GitLab has mapped notes' do
    let(:provider_issue) { super().merge(comments: 2) }

    it 'makes no GitHub request and removes nothing' do
      expect { execute }.not_to change { Note.count }

      expect(client).not_to have_received(:each_page)
      expect(client).not_to have_received(:issue_comment)
    end

    context 'when the issue changed since the last pass' do
      let(:unchanged) { false }
      let(:listed_comments) { [{ id: 301 }, { id: 303 }] }

      it 'removes the note of the deleted comment' do
        execute

        expect(Note.exists?(deleted_note.id)).to be(false)
        expect(kept_note.reload).to be_present
      end
    end
  end

  it 'makes no GitHub request for a noteable without mapped notes' do
    service.execute(create(:issue, project: project), provider_issue.merge(comments: 3), unchanged: false)

    expect(client).not_to have_received(:each_page)
  end

  context 'when GitHub has comments that are not synced yet' do
    let(:provider_issue) { super().merge(comments: 3) }
    let(:listed_comments) { [{ id: 301 }, { id: 302 }, { id: 303 }] }

    it 'removes nothing' do
      expect { execute }.not_to change { Note.count }

      expect(client).not_to have_received(:issue_comment)
    end
  end

  context 'when a comment is missing from the listing but GitHub still has it' do
    before do
      allow(client).to receive(:issue_comment).with('example/connected', 302).and_return({ id: 302 })
    end

    it 'keeps the note' do
      expect { execute }.not_to change { Note.count }
    end
  end

  context 'when the note is deleted on GitLab during the pass' do
    before do
      allow(client).to receive(:issue_comment).with('example/connected', 302) do
        deleted_note.destroy!
        raise Octokit::NotFound
      end
    end

    it 'skips the removal' do
      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      expect { execute }.not_to raise_error
    end
  end

  context 'when the comments span several pages' do
    before do
      allow(client).to receive(:each_page)
        .with(:issue_comments, nil, 'example/connected', 4)
        .and_yield(Gitlab::GithubImport::Client::Page.new([{ id: 300 }], 'https://api.github.com/x?page=2'))
        .and_yield(Gitlab::GithubImport::Client::Page.new([{ id: 301 }], nil))
    end

    it 'reads every page and renews the lease for each page and each check' do
      execute

      expect(Note.exists?(deleted_note.id)).to be(false)
      expect(kept_note.reload).to be_present
      expect(lease_context).to have_received(:renew!).exactly(3).times
    end
  end

  context 'when the noteable is a merge request' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project, iid: 5, imported_from: :github) }
    let!(:merge_request_note) { create(:note, project: project, noteable: merge_request, imported_from: :github) }
    let(:provider_issue) { { id: 102, number: 5, comments: 0, pull_request: { url: 'redacted' } } }

    before do
      map_note(merge_request_note, 401)
      allow(client).to receive(:each_page)
        .with(:issue_comments, nil, 'example/connected', 5)
        .and_yield(Gitlab::GithubImport::Client::Page.new([], nil))
      allow(client).to receive(:issue_comment).with('example/connected', 401).and_raise(Octokit::NotFound)
    end

    it 'removes only the merge request note' do
      service.execute(merge_request, provider_issue, unchanged: true)

      expect(Note.exists?(merge_request_note.id)).to be(false)
      expect(Note.where(id: [kept_note.id, deleted_note.id]).count).to eq(2)
    end
  end

  context 'when the lease is lost before the note is removed' do
    before do
      allow(lease_context).to receive(:verify!)
        .and_raise(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')
    end

    it 'keeps the note' do
      expect { execute }.to raise_error(Import::Sync::Repositories::ApplicationLease::LostLeaseError, 'lost')

      expect(deleted_note.reload).to be_present
    end
  end
end
