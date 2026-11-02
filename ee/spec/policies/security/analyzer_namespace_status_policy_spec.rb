# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AnalyzerNamespaceStatusPolicy, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:analyzer_group_status) { build(:analyzer_namespace_status, namespace: group) }

  subject(:policy) { described_class.new(build_stubbed(:user), analyzer_group_status) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
