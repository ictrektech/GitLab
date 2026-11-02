# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::DeleteUploadsLooseFkDeletedRecords, feature_category: :geo_replication do
  let(:deleted_records) { table(:loose_foreign_keys_deleted_records) }

  let!(:pending_upload_record) { create_deleted_record('public.uploads', status: 1) }
  let!(:another_pending_upload_record) { create_deleted_record('public.uploads', status: 1) }
  let!(:processed_upload_record) { create_deleted_record('public.uploads', status: 2) }
  let!(:pending_note_record) { create_deleted_record('public.notes', status: 1) }

  describe '#perform' do
    it 'deletes only the pending public.uploads records' do
      expect { perform_migration }.to change { deleted_records.count }.from(4).to(2)

      remaining = deleted_records.pluck(:fully_qualified_table_name, :status)
      expect(remaining).to contain_exactly(['public.uploads', 2], ['public.notes', 1])
    end

    it 'does not delete pending public.uploads records outside the cursor range' do
      end_cursor = [pending_note_record.partition, pending_note_record.attributes.fetch('id')]
      out_of_range_record = create_deleted_record('public.uploads', status: 1)

      expect { perform_migration(end_cursor: end_cursor) }.to change { deleted_records.count }.from(5).to(3)

      remaining_ids = deleted_records.where(fully_qualified_table_name: 'public.uploads', status: 1).pluck(:id)
      expect(remaining_ids).to contain_exactly(out_of_range_record.attributes.fetch('id'))
    end
  end

  def create_deleted_record(table_name, status:)
    deleted_records.create!(
      fully_qualified_table_name: table_name,
      primary_key_value: deleted_records.count + 1,
      status: status
    )
  end

  def perform_migration(end_cursor: [deleted_records.maximum(:partition), deleted_records.maximum(:id)])
    described_class.new(
      start_cursor: [deleted_records.minimum(:partition), 0],
      end_cursor: end_cursor,
      batch_table: :loose_foreign_keys_deleted_records,
      batch_column: :id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end
end
