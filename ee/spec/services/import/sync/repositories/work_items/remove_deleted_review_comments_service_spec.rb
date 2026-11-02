# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::WorkItems::RemoveDeletedReviewCommentsService, feature_category: :importers do
  let_it_be_with_reload(:repository) do
    create(:import_sync_repository, :oauth, provider_full_name: 'example/connected', provider_repository_xid: 77,
      provider_webhook_xid: 88)
  end

  let_it_be(:project) { repository.project }
  let_it_be(:merge_request) do
    create(:merge_request, source_project: project, iid: 5, imported_from: :github)
  end

  let!(:kept_note) { create_diff_note }
  let!(:deleted_note) { create_diff_note }
  let!(:kept_mapping) { map_note(kept_note, 401) }
  let!(:deleted_mapping) { map_note(deleted_note, 402) }

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:lease_context) do
    instance_double(Import::Sync::Repositories::ApplicationLease::Context, renew!: true, verify!: true)
  end

  let(:deliveries) { [delivery(1, 402)] }

  let(:service) { described_class.new(repository, lease_context: lease_context, client: client) }

  subject(:execute) { service.execute }

  before do
    repository.update_column(:webhook_deliveries_checked_at, 1.hour.ago)

    allow(client).to receive(:each_hook_delivery_page) do |_repo, _hook_id, &block|
      block.call(Gitlab::GithubImport::Client::Page.new(deliveries.map { |delivery| delivery[:summary] }, nil))
    end
    allow(client).to receive(:hook_delivery) do |_repo, _hook_id, delivery_id|
      deliveries.find { |delivery| delivery[:summary][:id] == delivery_id }[:details]
    end
  end

  def create_diff_note
    create(:legacy_diff_note_on_merge_request, project: project, noteable: merge_request, imported_from: :github)
  end

  def map_note(note, provider_object_xid)
    create(:import_sync_external_object, :review_comment, repository: repository, note: note,
      provider_object_xid: provider_object_xid)
  end

  def delivery(
    id, comment_id, event: 'pull_request_review_comment', action: 'deleted', status_code: 502,
    delivered_at: 10.minutes.ago
  )
    {
      summary: { id: id, event: event, action: action, status_code: status_code, delivered_at: delivered_at },
      details: { id: id, request: { payload: { action: action, comment: { id: comment_id } } } }
    }
  end

  it 'removes the note of a deleted review comment whose delivery failed', :aggregate_failures, :freeze_time do
    expect(Gitlab::GithubImport::Logger).to receive(:info).with(
      hash_including(message: 'removed GitHub review comment deleted on GitHub', note_id: deleted_note.id,
        provider_object_xid: 402)
    )

    execute

    expect(client).to have_received(:each_hook_delivery_page).with(77, 88)
    expect(client).to have_received(:hook_delivery).with(77, 88, 1)
    expect(Note.exists?(deleted_note.id)).to be(false)
    expect(Import::Sync::ExternalObject.exists?(deleted_mapping.id)).to be(false)
    expect(kept_note.reload).to be_present
    expect(repository.reload.webhook_deliveries_checked_at).to eq(Time.current)
    expect(lease_context).to have_received(:verify!)
  end

  context 'when the delivery did not fail or is for another event' do
    let(:deliveries) do
      [
        delivery(1, 402, status_code: 200),
        delivery(2, 402, action: 'edited'),
        delivery(3, 402, event: 'pull_request')
      ]
    end

    it 'does not fetch the delivery' do
      expect { execute }.not_to change { Note.count }

      expect(client).not_to have_received(:hook_delivery)
    end
  end

  context 'when the delivery has no comment id' do
    let(:deliveries) { [delivery(1, nil)] }

    it 'skips the delivery and moves the check time', :freeze_time do
      expect { execute }.not_to change { Note.count }

      expect(repository.reload.webhook_deliveries_checked_at).to eq(Time.current)
    end
  end

  context 'when the delivery was made before the last check' do
    let(:deliveries) { [delivery(1, 401), delivery(2, 402, delivered_at: 2.hours.ago)] }

    it 'stops reading at that delivery' do
      execute

      expect(Note.exists?(kept_note.id)).to be(false)
      expect(deleted_note.reload).to be_present
      expect(client).not_to have_received(:hook_delivery).with(77, 88, 2)
    end
  end

  context 'when the deliveries span several pages' do
    let(:deliveries) { [delivery(1, 402), delivery(2, 401, delivered_at: 2.hours.ago), delivery(3, 401)] }

    before do
      allow(client).to receive(:each_hook_delivery_page) do |_repo, _hook_id, &block|
        deliveries.each { |delivery| block.call(Gitlab::GithubImport::Client::Page.new([delivery[:summary]], nil)) }
      end
    end

    it 'stops at the first page with a delivery made before the last check' do
      execute

      expect(Note.exists?(deleted_note.id)).to be(false)
      expect(kept_note.reload).to be_present
      expect(client).not_to have_received(:hook_delivery).with(77, 88, 3)
      expect(lease_context).to have_received(:renew!).exactly(3).times
    end
  end

  context 'when deliveries were never checked' do
    let(:deliveries) { [delivery(1, 402, delivered_at: 2.days.ago)] }

    before do
      repository.update_column(:webhook_deliveries_checked_at, nil)
    end

    it 'reads every delivery GitHub kept' do
      execute

      expect(Note.exists?(deleted_note.id)).to be(false)
    end
  end

  context 'when the repository has no webhook' do
    before do
      repository.update_column(:provider_webhook_xid, nil)
    end

    it 'makes no GitHub request' do
      execute

      expect(client).not_to have_received(:each_hook_delivery_page)
    end
  end

  context 'when GitHub fails to list the deliveries' do
    let(:error) { Octokit::InternalServerError.new }

    before do
      allow(client).to receive(:each_hook_delivery_page).and_raise(error)
    end

    it 'tracks the error and checks the same deliveries on the next pass' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(error, import_sync_repository_id: repository.id)

      expect { execute }.not_to change { repository.reload.webhook_deliveries_checked_at }
    end
  end

  context 'when GitHub fails to return a delivery' do
    let(:error) { Octokit::InternalServerError.new }
    let(:deliveries) { [delivery(1, 401), delivery(2, 402)] }

    before do
      allow(client).to receive(:hook_delivery).with(77, 88, 1).and_raise(error)
    end

    it 'tracks the error, removes the other notes, and checks the same deliveries on the next pass',
      :aggregate_failures do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(error, import_sync_repository_id: repository.id, delivery_id: 1)

      expect { execute }.not_to change { repository.reload.webhook_deliveries_checked_at }

      expect(kept_note.reload).to be_present
      expect(Note.exists?(deleted_note.id)).to be(false)
    end

    context 'when GitHub rate limits the request' do
      let(:error) { Gitlab::GithubImport::RateLimitError.new('rate limited') }

      it 'raises so the pass is rescheduled' do
        expect { execute }.to raise_error(Gitlab::GithubImport::RateLimitError)

        expect(deleted_note.reload).to be_present
      end
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

  describe '#remove_comment' do
    let(:service) { described_class.new(repository, lease_context: lease_context) }

    it 'removes the note of a review comment deleted on GitHub without a GitHub request' do
      service.remove_comment(402)

      expect(Note.exists?(deleted_note.id)).to be(false)
      expect(kept_note.reload).to be_present
    end

    it 'does nothing for a comment without a synced note' do
      expect { service.remove_comment(999) }.not_to change { Note.count }
    end

    it 'does nothing when the note is deleted before it is removed' do
      allow(Import::Sync::ExternalObject).to receive(:for_provider).and_wrap_original do |method, **args|
        method.call(**args).tap { |mapping| Note.delete(mapping.note_id) }
      end

      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      service.remove_comment(402)

      expect(kept_note.reload).to be_present
    end
  end
end
