# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Geo::SkipSecondary, feature_category: :geo_replication do
  # The primary runs these jobs. Their rows replicate to Geo secondaries that use logical replication.
  it 'skips every batched background migration and background operation worker on a secondary' do
    workers = Gitlab::SidekiqConfig.workers.map(&:klass).select do |worker|
      worker.to_s.start_with?('Database::BatchedBackgroundMigration', 'Database::BackgroundOperation::')
    end

    expect(workers).to include(
      Database::BatchedBackgroundMigrationWorker,
      Database::BatchedBackgroundMigration::MainExecutionWorker,
      Database::BackgroundOperation::MainSchedulerWorker,
      Database::BackgroundOperation::MainOrchestratorWorker,
      Database::BackgroundOperation::CronEnqueueWorker
    )

    not_skipped = workers.reject { |worker| worker.instance_method(:perform).owner == described_class }

    expect(not_skipped).to be_empty
  end
end
