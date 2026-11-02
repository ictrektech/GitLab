# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::AddOnPurchasePolicy, feature_category: :seat_cost_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  context 'when namespace is present' do
    it { expect(described_class).to delegate_to(GroupPolicy) }
  end

  context 'when namespace is nil, in Self-Managed instance context' do
    let_it_be(:add_on_purchase) { create(:gitlab_subscription_add_on_purchase, :self_managed) }

    subject { described_class.new(owner, add_on_purchase) }

    it { is_expected.to delegate_to(GlobalPolicy) }
  end
end
