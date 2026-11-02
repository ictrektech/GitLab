# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespace::RootStorageStatisticsPolicy, feature_category: :consumables_cost_management do
  let(:user) { build_stubbed(:user) }
  let(:statistics) { build_stubbed(:namespace_root_storage_statistics, namespace: namespace) }

  subject(:policy) { described_class.new(user, statistics) }

  context 'when the namespace is a personal namespace' do
    let(:namespace) { build_stubbed(:user_namespace) }

    it { is_expected.to delegate_to(Namespaces::UserNamespacePolicy) }
  end

  context 'when the namespace is a group' do
    let(:namespace) { build_stubbed(:group) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end
end
