# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptionPolicy, :saas, feature_category: :consumables_cost_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:subscription) { create(:gitlab_subscription, namespace: group) }

  subject(:policy) { described_class.new(owner, subscription) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
