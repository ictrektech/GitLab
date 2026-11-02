# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::RefreshDailyTotalsCronWorker, feature_category: :consumables_cost_management do
  let(:worker) { described_class.new }
  let(:local_persistence_enabled) { true }

  before do
    allow_next_instance_of(Gitlab::BillingEvents::Client) do |client|
      allow(client).to receive(:local_persistence_enabled?).and_return(local_persistence_enabled)
    end
  end

  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '#perform' do
    it 'refreshes the daily totals' do
      expect_next_instance_of(Utilization::BillableUsage::RefreshDailyTotalsService) do |service|
        expect(service).to receive(:execute).and_return(ServiceResponse.success(payload: {}))
      end

      worker.perform
    end

    it 'logs the result' do
      create(:billable_usage_daily_namespace_aggregate)

      expect(worker).to receive(:log_extra_metadata_on_done)
        .with(:result, { days_refreshed: 1, over_time: false })

      worker.perform
    end

    it 'totals the per-namespace rows' do
      create(:billable_usage_daily_namespace_aggregate, root_namespace_id: 1, quantity: 2)
      create(:billable_usage_daily_namespace_aggregate, root_namespace_id: 2, quantity: 3)

      worker.perform

      expect(Utilization::BillableUsage::DailyTotal.sole).to have_attributes(quantity: 5)
    end

    context 'when local persistence is disabled' do
      let(:local_persistence_enabled) { false }

      it 'does not refresh the daily totals' do
        expect(Utilization::BillableUsage::RefreshDailyTotalsService).not_to receive(:new)

        worker.perform
      end
    end
  end

  it_behaves_like 'an idempotent worker'
end
