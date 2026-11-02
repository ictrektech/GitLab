# frozen_string_literal: true

require "spec_helper"

RSpec.describe Admin::UserEntity, feature_category: :user_management do
  let_it_be(:user) { build_stubbed(:user) }

  let(:request) { double('request') }

  let(:entity) do
    described_class.new(user, request: request, current_user: current_user)
  end

  describe '#as_json #security' do
    subject(:keys) { entity.as_json&.keys }

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(current_user, :read_incident_management_oncall_schedule, :global).and_return(oncall_allowed)
      allow(Ability).to receive(:allowed?)
        .with(current_user, :read_incident_management_escalation_policy, :global).and_return(escalation_allowed)
    end

    let(:current_user) { build_stubbed(:admin) }
    let(:oncall_allowed) { false }
    let(:escalation_allowed) { false }

    context 'when the current user can read on-call schedules instance-wide' do
      let(:oncall_allowed) { true }

      it { is_expected.to include(:oncall_schedules) }
    end

    context 'when the current user cannot read on-call schedules instance-wide' do
      it { is_expected.not_to include(:oncall_schedules) }
    end

    context 'when the current user can read escalation policies instance-wide' do
      let(:escalation_allowed) { true }

      it { is_expected.to include(:escalation_policies) }
    end

    context 'when the current user cannot read escalation policies instance-wide' do
      it { is_expected.not_to include(:escalation_policies) }
    end
  end
end
