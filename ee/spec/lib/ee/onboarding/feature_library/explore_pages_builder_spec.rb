# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::ExplorePagesBuilder, feature_category: :onboarding do
  describe '.available?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:member) { create(:user) }
    let_it_be(:non_member) { create(:user) }
    let_it_be(:admin) { create(:admin) }
    let_it_be(:root_group) { create(:group, :public, guests: member) }
    let_it_be(:subgroup) { create(:group, :public, parent: root_group) }

    subject(:available) { described_class.available?(user: viewer, resource: resource) }

    where(:viewer, :resource, :expected) do
      ref(:member)     | ref(:root_group) | true
      ref(:non_member) | ref(:root_group) | false
      ref(:admin)      | ref(:root_group) | false
      nil              | ref(:root_group) | false
      ref(:member)     | nil              | false
    end

    with_them do
      it { is_expected.to be(expected) }
    end

    context 'when the admin is in admin mode', :enable_admin_mode do
      let(:viewer) { admin }
      let(:resource) { root_group }

      it { is_expected.to be(true) }
    end

    context 'when the flag is enabled for the root group only' do
      let(:viewer) { member }

      before do
        stub_feature_flags(feature_catalog_explore_pages: root_group)
      end

      context 'with a subgroup' do
        let(:resource) { subgroup }

        it { is_expected.to be(true) }
      end

      context 'with another root group' do
        let(:resource) { create(:group, :public, guests: member) }

        it { is_expected.to be(false) }
      end
    end

    context 'when the flag is disabled' do
      let(:viewer) { member }
      let(:resource) { root_group }

      before do
        stub_feature_flags(feature_catalog_explore_pages: false)
      end

      it { is_expected.to be(false) }
    end
  end
end
