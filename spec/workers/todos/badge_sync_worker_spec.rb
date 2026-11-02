# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Todos::BadgeSyncWorker, feature_category: :notifications do
  let_it_be(:user) { create(:user) }

  subject(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [user.id] }
  end

  it 'is not deferred on database health signals' do
    expect(described_class.defer_on_database_health_signal?).to be(false)
  end

  it 'deduplicates per user including scheduled jobs, rescheduling once' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(
      if_deduplicated: :reschedule_once, including_scheduled: true
    )
  end

  describe '#perform' do
    it 'runs the badge update service and logs its tallies' do
      response = ServiceResponse.success(
        payload: { subscription_count: 0, results: { 'skipped_no_subscription' => 1 }, apns_results: {} }
      )
      service = instance_double(::Notifications::MobilePush::SendBadgeUpdateService, execute: response)
      expect(::Notifications::MobilePush::SendBadgeUpdateService)
        .to receive(:new).with(user.id).and_return(service)

      expect(worker).to receive(:log_extra_metadata_on_done).with(:subscription_count, 0)
      expect(worker).to receive(:log_extra_metadata_on_done).with(:results, { 'skipped_no_subscription' => 1 })
      expect(worker).to receive(:log_extra_metadata_on_done).with(:apns_results, {})

      worker.perform(user.id)
    end
  end
end
