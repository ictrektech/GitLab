# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundOperation::MergeRequestCleanupSchedulesDeleteCompleted, :background_operation,
  feature_category: :code_review_workflow do
  let(:merge_requests) { table(:merge_requests) }
  let(:cleanup_schedules) { table(:merge_request_cleanup_schedules) }

  let!(:organization) { table(:organizations).create!(name: 'organization', path: 'organization') }
  let!(:namespace) do
    table(:namespaces).create!(name: 'test', path: 'test', type: 'Group', organization_id: organization.id)
  end

  let!(:project) do
    table(:projects).create!(
      namespace_id: namespace.id,
      project_namespace_id: namespace.id,
      organization_id: organization.id
    )
  end

  let(:statuses) { MergeRequest::CleanupSchedule::STATUSES }
  let(:old_completion) { described_class::RETENTION_PERIOD.ago - 1.day }
  let(:recent_completion) { described_class::RETENTION_PERIOD.ago + 1.day }

  def operation
    described_class.new(
      min_cursor: [cleanup_schedules.minimum(:merge_request_id)],
      max_cursor: [cleanup_schedules.maximum(:merge_request_id)],
      batch_table: :merge_request_cleanup_schedules,
      batch_column: :merge_request_id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ::ApplicationRecord.connection
    )
  end

  def create_schedule(status:, completed_at: nil)
    merge_request = merge_requests.create!(
      target_project_id: project.id,
      target_branch: 'master',
      source_branch: "feature-#{SecureRandom.hex(4)}"
    )

    cleanup_schedules.create!(
      merge_request_id: merge_request.id,
      project_id: project.id,
      scheduled_at: 1.year.ago,
      status: status,
      completed_at: completed_at
    )
  end

  it 'deletes completed rows past the retention period' do
    # Three eligible rows so more than one sub-batch (size 2) has to delete something.
    deleted = Array.new(3) { create_schedule(status: statuses[:completed], completed_at: old_completion) }

    operation.perform

    expect(cleanup_schedules.where(merge_request_id: deleted.map(&:merge_request_id))).to be_empty
  end

  it 'keeps every row that is not a completed row past the retention period', :aggregate_failures do
    recently_completed = create_schedule(status: statuses[:completed], completed_at: recent_completion)
    unstarted = create_schedule(status: statuses[:unstarted])
    running = create_schedule(status: statuses[:running])
    failed = create_schedule(status: statuses[:failed])
    # Cannot occur through the state machine; proves the status filter alone never deletes.
    failed_with_old_timestamp = create_schedule(status: statuses[:failed], completed_at: old_completion)

    operation.perform

    [recently_completed, unstarted, running, failed, failed_with_old_timestamp].each do |schedule|
      expect(cleanup_schedules.exists?(schedule.merge_request_id)).to be(true)
    end
  end

  context 'when the ops feature flag is disabled' do
    before do
      stub_feature_flags(merge_request_cleanup_schedules_retention: false)
    end

    it 'deletes nothing' do
      create_schedule(status: statuses[:completed], completed_at: old_completion)

      expect { operation.perform }.not_to change { cleanup_schedules.count }
    end
  end
end
