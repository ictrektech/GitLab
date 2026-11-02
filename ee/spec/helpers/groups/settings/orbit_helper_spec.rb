# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Settings::OrbitHelper, feature_category: :knowledge_graph do
  describe '#group_orbit_settings_data' do
    let_it_be(:group) { build_stubbed(:group) }
    let_it_be(:user) { build_stubbed(:user) }

    subject(:data) { helper.group_orbit_settings_data(group) }

    before do
      allow(helper).to receive_messages(current_user: user, can?: false)
    end

    it 'includes the paths and lead data the page needs' do
      expect(data).to include(
        group_full_path: group.full_path,
        orbit_path: helper.dashboard_orbit_path,
        usage_quotas_path: helper.group_usage_quotas_path(group),
        duo_settings_path: helper.group_settings_gitlab_duo_path(group)
      )
      expect(data).to have_key(:hand_raise_lead_user)
      expect(data).to have_key(:hand_raise_lead_submit_path)
    end

    describe 'orbit_platform' do
      subject(:platform) { ::Gitlab::Json::SafeParser.parse(data[:orbit_platform]) }

      context 'on GitLab.com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it { expect(platform).to eq('saas' => true) }
      end

      context 'on GitLab Self-Managed' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it { expect(platform).to eq('saas' => false) }
      end

      context 'when the instance trial flow is on', :request_store do
        let(:current_license) { ::License.current || build(:license) }

        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          stub_licensed_features(orbit: true)
          stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)
          stub_config(knowledge_graph: { 'enabled' => true })
          allow(::License).to receive(:current).and_return(current_license)
          allow(current_license).to receive(:online_cloud_license?).and_return(true)
        end

        it 'asks CustomersDot nothing' do
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

          expect(platform).to eq('saas' => false)
        end
      end
    end

    describe 'duo_available' do
      context 'when the user can access Duo features' do
        before do
          allow(helper).to receive(:can?).with(user, :access_duo_features, group).and_return(true)
        end

        it { expect(data[:duo_available]).to eq('true') }
      end

      context 'when the user cannot access Duo features' do
        before do
          allow(helper).to receive(:can?).with(user, :access_duo_features, group).and_return(false)
        end

        it { expect(data[:duo_available]).to eq('false') }
      end
    end
  end
end
