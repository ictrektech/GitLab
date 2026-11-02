# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Widgets::EscalationPolicy, feature_category: :incident_management do
  let_it_be(:work_item) { create(:work_item, :incident) }

  describe '.type' do
    it { expect(described_class.type).to eq(:escalation_policy) }
  end

  describe '#type' do
    it { expect(described_class.new(work_item).type).to eq(:escalation_policy) }
  end

  describe '#escalation_policy' do
    subject { described_class.new(work_item).escalation_policy }

    context 'when escalation status is not set' do
      it { is_expected.to be_nil }
    end

    context 'when escalation policy is set' do
      let!(:escalation_status) { create(:incident_management_issuable_escalation_status, :paging, issue: work_item) }

      before do
        work_item.reload
      end

      it { is_expected.to eq(escalation_status.policy) }
    end
  end
end
