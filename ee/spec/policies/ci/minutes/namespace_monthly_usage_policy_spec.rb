# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Minutes::NamespaceMonthlyUsagePolicy, feature_category: :hosted_runners do
  let(:group) { create(:group, :private, name: 'test') }
  let(:current_user) { create(:user) }

  let(:namespace_monthly_usage) do
    create(:ci_namespace_monthly_usage, namespace: group)
  end

  subject(:policy) do
    described_class.new(current_user, namespace_monthly_usage)
  end

  it { is_expected.to delegate_to(GroupPolicy) }

  context 'with an owner' do
    before do
      group.add_owner(current_user)
    end

    it { expect_allowed(:read_usage) }
  end

  context 'with a developer' do
    before do
      group.add_developer(current_user)
    end

    it { expect_disallowed(:read_usage) }
  end

  context "with a user's namespace" do
    let(:namespace_monthly_usage) do
      create(:ci_namespace_monthly_usage, namespace: current_user.namespace)
    end

    it { is_expected.to delegate_to(Namespaces::UserNamespacePolicy) }
    it { expect_allowed(:read_usage) }
  end

  context 'with a different namespace' do
    let(:namespace_monthly_usage) do
      create(:ci_namespace_monthly_usage, namespace: create(:user).namespace)
    end

    it { expect_disallowed(:read_usage) }
  end
end
