# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::UserPreferencePolicy, feature_category: :team_planning do
  let(:user) { build_stubbed(:user) }
  let(:user_preference) { build_stubbed(:work_item_user_preference, namespace: namespace, user: user) }

  subject(:policy) { described_class.new(user, user_preference) }

  context 'when namespace is a group' do
    let(:namespace) { build_stubbed(:group) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end

  context 'when namespace is a project namespace' do
    let(:namespace) { build_stubbed(:project_namespace) }

    it { is_expected.to delegate_to(Namespaces::ProjectNamespacePolicy) }
  end

  context 'when namespace is a user namespace' do
    let(:namespace) { build_stubbed(:user_namespace) }

    it { is_expected.to delegate_to(Namespaces::UserNamespacePolicy) }
  end
end
