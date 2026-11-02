# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::EntitlementPolicy, feature_category: :secrets_management do
  let(:user) { build(:user) }
  let(:entitlement) { SecretsManagement::Entitlement.new(state: :trial) }
  let(:adapter) { Types::SecretsManagement::EntitlementType::Adapter.new(entitlement: entitlement, group: group) }

  subject(:policy) { described_class.new(user, adapter) }

  context 'with a top-level group entitlement' do
    let(:group) { build(:group) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end

  context 'with the instance-wide entitlement' do
    let(:group) { nil }

    it { is_expected.to delegate_to(GlobalPolicy) }
  end
end
