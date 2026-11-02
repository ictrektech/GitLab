# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::Availability, feature_category: :consumables_cost_management do
  describe '.enabled?' do
    subject(:enabled) { described_class.enabled? }

    before do
      stub_feature_flags(billable_usage_export: flag_enabled)
      allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
        allow(client).to receive(:local_persistence_enabled?).and_return(persistence_enabled)
      end
    end

    context 'with the flag enabled and local persistence available' do
      let(:flag_enabled) { true }
      let(:persistence_enabled) { true }

      it { is_expected.to be(true) }
    end

    context 'with the flag disabled' do
      let(:flag_enabled) { false }
      let(:persistence_enabled) { true }

      it { is_expected.to be(false) }
    end

    context 'when the instance does not persist billable usage locally' do
      let(:flag_enabled) { true }
      let(:persistence_enabled) { false }

      it { is_expected.to be(false) }
    end
  end
end
