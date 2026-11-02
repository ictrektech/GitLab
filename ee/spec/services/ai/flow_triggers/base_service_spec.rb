# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::BaseService, feature_category: :dap_triggers do
  let(:service) { described_class.new }

  describe '#flow_changes' do
    it 'returns no diff when a recorded change does not alter the flow descriptor' do
      trigger = build_stubbed(:ai_flow_trigger, config_path: 'ci/flow.yml', ai_catalog_item_consumer: nil)
      allow(trigger).to receive(:previous_changes).and_return('config_path' => %w[ci/flow.yml ci/flow.yml])

      expect(service.send(:flow_changes, trigger)).to eq({})
    end
  end

  describe '#flow_descriptor' do
    it 'omits the name when the catalog item consumer no longer exists' do
      result = service.send(:flow_descriptor, nil, non_existing_record_id)

      expect(result).to eq(
        type: 'ai_catalog_item', ai_catalog_item_consumer_id: non_existing_record_id, name: nil
      )
    end
  end

  describe '#schedule_changes' do
    it 'records a schedule introduced on a previously unscheduled filter' do
      trigger = build_stubbed(:ai_flow_trigger)
      allow(trigger).to receive(:previous_changes).and_return(
        'filter' => [nil, { 'scheduled' => { 'frequency' => 'DAILY' } }]
      )

      expect(service.send(:schedule_changes, trigger)).to eq(
        schedule: { from: nil, to: { 'frequency' => 'DAILY' } }
      )
    end

    it 'records a schedule removed down to a non-hash filter' do
      trigger = build_stubbed(:ai_flow_trigger)
      allow(trigger).to receive(:previous_changes).and_return(
        'filter' => [{ 'scheduled' => { 'frequency' => 'DAILY' } }, nil]
      )

      expect(service.send(:schedule_changes, trigger)).to eq(
        schedule: { from: { 'frequency' => 'DAILY' }, to: nil }
      )
    end
  end

  describe '#service_account_changes' do
    it 'returns no diff when a recorded change does not alter the effective account' do
      trigger = build_stubbed(:ai_flow_trigger)
      allow(trigger).to receive(:previous_changes).and_return('user_id' => [trigger.user_id, trigger.user_id])

      expect(service.send(:service_account_changes, trigger)).to eq({})
    end
  end

  describe '#effective_account_id' do
    it 'returns nil when the catalog item consumer no longer exists' do
      trigger = build_stubbed(:ai_flow_trigger,
        user: nil,
        autonomous_service_account_id: nil,
        ai_catalog_item_consumer_id: non_existing_record_id)

      expect(service.send(:effective_account_id, trigger, 0)).to be_nil
    end
  end

  describe '#account_descriptor' do
    it 'omits the username when the account no longer exists' do
      result = service.send(:account_descriptor, non_existing_record_id)

      expect(result).to eq(id: non_existing_record_id, username: nil)
    end
  end
end
