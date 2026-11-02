# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AttributePolicy, feature_category: :security_asset_inventories do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:group) { create(:group, parent: root_group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:attribute) { build_stubbed(:security_attribute, namespace: root_group) }

  subject { described_class.new(user, attribute) }

  before do
    stub_licensed_features(security_attributes: true)
  end

  it { is_expected.to delegate_to(GroupPolicy) }

  context 'when user is owner of subgroup' do
    before_all do
      group.add_owner(user)
    end

    it { is_expected.to be_disallowed(:read_security_attribute) }
  end
end
