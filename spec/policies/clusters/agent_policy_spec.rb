# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Clusters::AgentPolicy, feature_category: :deployment_management do
  let(:cluster_agent) { create(:cluster_agent, name: 'agent') }
  let(:user) { create(:admin) }
  let(:policy) { described_class.new(user, cluster_agent) }
  let(:project) { cluster_agent.project }

  it { expect(policy).to delegate_to(ProjectPolicy) }

  describe 'rules' do
    it { expect(policy).to be_disallowed :read_cluster_agent }

    context 'when agent is ci_access authorized for project members' do
      before do
        allow(cluster_agent).to receive(:ci_access_authorized_for?).with(user).and_return(true)
      end

      it { expect(policy).to be_allowed :read_cluster_agent }
    end

    context 'when agent is user_access authorized for project members' do
      before do
        allow(cluster_agent).to receive(:user_access_authorized_for?).with(user).and_return(true)
      end

      it { expect(policy).to be_allowed :read_cluster_agent }
    end
  end
end
