# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Clusters::ClusterPolicy, :models, feature_category: :deployment_management do
  let(:user) { build_stubbed(:user) }

  subject(:policy) { described_class.new(user, cluster) }

  context 'when the cluster belongs to a project' do
    let(:cluster) { build_stubbed(:cluster, :project) }

    it { is_expected.to delegate_to(ProjectPolicy) }
  end

  context 'when the cluster belongs to a group' do
    let(:cluster) { build_stubbed(:cluster, :group) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end

  context 'when the cluster is an instance cluster' do
    let(:cluster) { build_stubbed(:cluster, :instance) }

    it { is_expected.to delegate_to(Clusters::InstancePolicy) }
  end
end
