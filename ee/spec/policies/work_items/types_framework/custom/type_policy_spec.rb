# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::TypesFramework::Custom::TypePolicy, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }

  subject(:policy) { described_class.new(user, custom_type) }

  context 'with namespace-scoped custom type' do
    let_it_be(:group) { create(:group, :private, maintainers: user) }
    let_it_be(:custom_type) { create(:work_item_custom_type, namespace: group) }

    it { is_expected.to delegate_to(GroupPolicy) }

    context 'when the feature is licensed' do
      before do
        stub_licensed_features(configurable_work_item_types: true, work_item_status: true)
      end

      it { expect_allowed(:admin_work_item_lifecycle) }
    end

    context 'when the feature is not licensed' do
      before do
        stub_licensed_features(configurable_work_item_types: false, work_item_status: true)
      end

      it { expect_disallowed(:admin_work_item_lifecycle) }
    end
  end

  context 'with organization-scoped custom type' do
    let(:custom_type) { build_stubbed(:work_item_custom_type, :with_organization) }

    it { is_expected.to delegate_to(Organizations::OrganizationPolicy) }
  end
end
