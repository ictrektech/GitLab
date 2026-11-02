# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::ExternalObject, feature_category: :importers do
  let(:repository) { create(:import_sync_repository) }
  let(:issue) { create(:issue, project: repository.project) }

  describe 'associations' do
    # Built on an unsaved repository so populate_sharding_key's source lookup can't
    # silently repopulate project_id and mask a missing `required: true`.
    subject(:mapping) { build(:import_sync_external_object, repository: build(:import_sync_repository)) }

    it { is_expected.to belong_to(:repository).class_name('Import::Sync::Repository').required }
    it { is_expected.to belong_to(:issue).optional }
    it { is_expected.to belong_to(:merge_request).optional }
    it { is_expected.to belong_to(:note).optional }
  end

  describe 'sharding key' do
    subject(:mapping) { build(:import_sync_external_object, repository: repository, project_id: nil) }

    it { is_expected.to populate_sharding_key(:project_id).with(repository.project_id) }
  end

  describe 'kind' do
    subject(:mapping) { build(:import_sync_external_object, repository: repository) }

    it 'defines the provider object kinds' do
      is_expected.to define_enum_for(:kind)
        .with_values(issue: 0, pull_request: 1, issue_comment: 2, review_comment: 3, review: 4).with_prefix
    end
  end

  describe 'validations' do
    it 'requires a positive integer provider object id' do
      is_expected.to validate_numericality_of(:provider_object_xid).only_integer.is_greater_than(0)
    end

    it 'rejects a non-positive provider object id at the database level' do
      mapping = build(:import_sync_external_object, repository: repository, issue: issue, provider_object_xid: -1)

      expect { mapping.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'requires exactly one of issue, merge request, or note' do
      mapping = build(:import_sync_external_object, repository: repository, issue: nil)

      expect(mapping).not_to be_valid
      expect(mapping.errors[:base]).to include('Exactly one of issue, merge_request, note must be present')
    end

    it 'rejects that check at the database level too' do
      mapping = build(:import_sync_external_object, repository: repository, issue: nil)

      expect { mapping.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'rejects a mapping across project shards' do
      mapping = build(
        :import_sync_external_object,
        repository: repository,
        project_id: create(:project).id,
        issue: issue
      )

      expect(mapping).not_to be_valid
      expect(mapping.errors[:repository]).to include('must belong to the same project.')
    end

    it 'rejects the same provider object claiming two different native records' do
      create(:import_sync_external_object, repository: repository, kind: :issue, provider_object_xid: 123, issue: issue)
      duplicate = build(
        :import_sync_external_object,
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        issue: create(:issue, project: repository.project)
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider_object_xid]).to include('has already been taken')
    end

    it 'does not let different provider identities claim one native issue' do
      create(:import_sync_external_object, repository: repository, kind: :issue, provider_object_xid: 123, issue: issue)
      conflicting_mapping = build(
        :import_sync_external_object,
        repository: repository,
        kind: :issue,
        provider_object_xid: 456,
        issue: issue
      )

      expect(conflicting_mapping).not_to be_valid
      expect(conflicting_mapping.errors[:issue_id]).to include('has already been taken')
    end

    it 'does not let different provider identities claim one native merge request' do
      merge_request = create(:merge_request, source_project: repository.project, target_project: repository.project)
      create(:import_sync_external_object, :pull_request, repository: repository, provider_object_xid: 123,
        merge_request: merge_request)
      conflicting_mapping = build(
        :import_sync_external_object,
        :pull_request,
        repository: repository,
        provider_object_xid: 456,
        merge_request: merge_request
      )

      expect(conflicting_mapping).not_to be_valid
      expect(conflicting_mapping.errors[:merge_request_id]).to include('has already been taken')
    end

    it 'does not let different provider identities claim one native note' do
      note = create(:note, project: repository.project)
      create(:import_sync_external_object, :issue_comment, repository: repository, provider_object_xid: 123, note: note)
      conflicting_mapping = build(
        :import_sync_external_object,
        :issue_comment,
        repository: repository,
        provider_object_xid: 456,
        note: note
      )

      expect(conflicting_mapping).not_to be_valid
      expect(conflicting_mapping.errors[:note_id]).to include('has already been taken')
    end
  end

  describe '#local_record' do
    it 'returns whichever of the three columns is set' do
      mapping = create(:import_sync_external_object, repository: repository, issue: issue)

      expect(mapping.local_record).to eq(issue)
    end
  end

  describe '.for_local_record' do
    it 'finds the mapping currently claiming a native record in the repository' do
      mapping = create(:import_sync_external_object, repository: repository, issue: issue)

      expect(described_class.for_local_record(repository: repository, local_record: issue)).to eq(mapping)
    end

    it 'returns nil when the record has no mapping yet' do
      expect(described_class.for_local_record(repository: repository, local_record: issue)).to be_nil
    end
  end

  describe '.comments_on' do
    it 'returns the comment mappings for notes on the noteable' do
      project = repository.project
      mapped = create(:import_sync_external_object, :issue_comment, repository: repository,
        note: create(:note, project: project, noteable: issue))
      create(:note, project: project, noteable: issue)
      create(:import_sync_external_object, :issue_comment, repository: repository,
        note: create(:note, project: project, noteable: create(:issue, project: project)))
      create(:import_sync_external_object, repository: repository, issue: issue)

      expect(described_class.comments_on(repository: repository, noteable: issue)).to contain_exactly(mapped)
    end
  end

  describe '.record!' do
    it 'records and resolves a stable provider mapping idempotently' do
      first = described_class.record!(
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        local_record: issue,
        provider_updated_at: 1.minute.ago
      )
      second = described_class.record!(
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        local_record: issue,
        provider_updated_at: Time.current
      )

      expect(second).to eq(first)
      expect(second.local_record).to eq(issue)
      expect(described_class.where(provider_object_xid: 123).count).to eq(1)
    end

    it 're-resolves the existing mapping when update_mapping! races against a concurrent insert' do
      concurrent_mapping = create(
        :import_sync_external_object,
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        issue: issue
      )
      original_update_mapping = described_class.method(:update_mapping!)
      call_count = 0

      # Both writers' initial for_provider check misses (the row doesn't exist yet
      # from either writer's point of view), so both proceed to insert; only one
      # write can win the unique index, and the loser's update_mapping! must raise
      # ActiveRecord::RecordNotUnique instead of silently overwriting the winner.
      allow(described_class).to receive(:for_provider).and_return(nil, concurrent_mapping)
      allow(described_class).to receive(:update_mapping!) do |mapping, **kwargs|
        call_count += 1
        raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint' if call_count == 1

        original_update_mapping.call(mapping, **kwargs)
      end

      mapping = described_class.record!(
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        local_record: issue,
        provider_updated_at: Time.current
      )

      expect(mapping).to eq(concurrent_mapping)
      expect(described_class.where(provider_object_xid: 123).count).to eq(1)
    end

    it 're-resolves the existing mapping when a concurrent writer wins the validation-level race' do
      concurrent_mapping = nil
      call_count = 0
      original_for_provider = described_class.method(:for_provider)

      # Both writers' initial for_provider check misses; a second writer then commits
      # its own row for this provider identity before this writer's own uniqueness
      # validation runs, so update_mapping! raises RecordInvalid (not RecordNotUnique)
      # because the conflict is caught by validation before it ever reaches the
      # database constraint. record! must recover from this the same way.
      allow(described_class).to receive(:for_provider) do |**kwargs|
        call_count += 1
        next original_for_provider.call(**kwargs) if call_count > 1

        concurrent_mapping = create(
          :import_sync_external_object,
          repository: repository,
          kind: :issue,
          provider_object_xid: 123,
          issue: issue
        )
        nil
      end

      mapping = described_class.record!(
        repository: repository,
        kind: :issue,
        provider_object_xid: 123,
        local_record: issue,
        provider_updated_at: Time.current
      )

      expect(mapping).to eq(concurrent_mapping)
      expect(described_class.where(provider_object_xid: 123).count).to eq(1)
    end

    it 'does not swallow a validation failure unrelated to the provider identity race' do
      other_issue = create(:issue, project: repository.project)
      create(:import_sync_external_object, repository: repository, kind: :issue, provider_object_xid: 999,
        issue: other_issue)

      expect do
        described_class.record!(
          repository: repository,
          kind: :issue,
          provider_object_xid: 123,
          local_record: other_issue,
          provider_updated_at: Time.current
        )
      end.to raise_error(ActiveRecord::RecordInvalid, /Issue has already been taken/)
    end

    it 'records a merge request mapping' do
      merge_request = create(:merge_request, source_project: repository.project, target_project: repository.project)

      mapping = described_class.record!(
        repository: repository,
        kind: :pull_request,
        provider_object_xid: 123,
        local_record: merge_request,
        provider_updated_at: Time.current
      )

      expect(mapping.local_record).to eq(merge_request)
    end

    it 'records a note mapping' do
      note = create(:note, project: repository.project)

      mapping = described_class.record!(
        repository: repository,
        kind: :issue_comment,
        provider_object_xid: 123,
        local_record: note,
        provider_updated_at: Time.current
      )

      expect(mapping.local_record).to eq(note)
    end

    it 'raises for a local record type with no mapping column' do
      expect do
        described_class.record!(
          repository: repository,
          kind: :issue,
          provider_object_xid: 123,
          local_record: create(:user),
          provider_updated_at: Time.current
        )
      end.to raise_error(ArgumentError, /unsupported local record type/)
    end

    it 're-raises when the provider identity race resolves to no mapping at all' do
      # A RecordNotUnique caused by something other than the provider identity index
      # (for example, an unrelated unique constraint) must not be swallowed: the
      # retried for_provider lookup finds nothing, so the original error propagates.
      allow(described_class).to receive(:update_mapping!)
        .and_raise(ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint')
      allow(described_class).to receive(:for_provider).and_return(nil)

      expect do
        described_class.record!(
          repository: repository,
          kind: :issue,
          provider_object_xid: 123,
          local_record: issue,
          provider_updated_at: Time.current
        )
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
