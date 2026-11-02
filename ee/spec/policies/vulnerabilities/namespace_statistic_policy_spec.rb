# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::NamespaceStatisticPolicy, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:namespace_statistic) { build(:vulnerability_namespace_statistic, group: group) }

  subject(:policy) { described_class.new(build_stubbed(:user), namespace_statistic) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
