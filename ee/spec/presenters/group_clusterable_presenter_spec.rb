# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GroupClusterablePresenter, feature_category: :environment_management do
  include Gitlab::Routing.url_helpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, maintainers: user) }

  let(:cluster) { build_stubbed(:cluster, :provided_by_gcp, :group, groups: [group]) }
  let(:presenter) { described_class.new(group) }

  describe '#environments_cluster_path' do
    subject { presenter.environments_cluster_path(cluster) }

    before do
      allow(presenter).to receive(:current_user).and_return(user)

      stub_licensed_features(cluster_deployments: feature_available)
    end

    context 'cluster_deployments feature is available' do
      let(:feature_available) { true }

      it { is_expected.to eq(environments_group_cluster_path(group, cluster)) }
    end

    context 'cluster_deployments feature is not available' do
      let(:feature_available) { false }

      it { is_expected.to be_nil }
    end
  end
end
